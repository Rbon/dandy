# TODO:
#   Write a better description for get_phrase.
#   "Again" command.
#   Spells. 


## BUGS:
## Un-numlock'd numberpad keys still insert text into the line editor, because
## they make two keypresses somehow.


require "json"
require "curses"

class Actions
  # Makes a speudorandom dice roll of any arbitrary count, faces, and modifiers.
  #
  # notation - the dice notation, as a String.
  #
  # Examples
  #
  #   roll("4d8 + 2")
  #   # => [16, "| [4, 3, 1, 6] + 2"]
  #
  # Returns an Array with two items--an Integer sum of the rolls, and a nicely
  #   formatted String of individual rolls, and the modifier, if there was one.
  def self.roll_dice(notation)
    sum = 0
    operator = nil
    mod = nil
    count, faces = notation.delete(" ").split("d")
    rolls = []
    
    ["+","-"].each do |symbol|
      if faces.include?(symbol)
        faces, mod = faces.split(symbol)
        operator = symbol
      end
    end
    
    (1..count.to_i).each do
      roll = rand(1..faces.to_i)
      rolls << roll
      sum  += roll
    end
    
    rolls = "| #{rolls}"
    
    case operator
    when "+"
      sum += mod.to_i
      rolls += " + #{mod}"
    when "-"
      sum -= mod.to_i
      rolls += " - #{mod}"
    end
    
    return sum, rolls
  end

  # Rolls to hit, i.e. 1d20 + attack mod.
  #   Automatically re-rolls for crits and fumbles.
  #
  # attack_mod - An Integer of the total attack modifier for the action being
  #              performed.
  #
  # Example
  #
  #   hit(2)
  #   # => 16 to hit [14 + 2]
  #
  # Returns a multiple-line String detailing how the roll went.
  def self.hit(attack_mod, advantage = nil)
    result = ""
    roll = roll_dice("1d20 + #{attack_mod}")
    result += "#{roll[0]} to hit #{roll[1]}"
    
    if roll[0] == 20 + attack_mod
      result += "\nRolling to confirm crit...\n"
      result += hit(attack_mod)
      
    elsif roll[0] == 1 + attack_mod
      result += "\nRolling to confirm fumble...\n"
      result += hit(attack_mod)
    end
    
    if advantage
      advantage = Main.get_phrase(advantage, ["advantage", "disadvantage"])[0]
      case advantage
      when "advantage"
        result += "\nRolling for advantage...\n"
        result += hit(attack_mod)
      when "disadvantage"
        result += "\nRolling for disadvantage...\n"
        result += hit(attack_mod)
      end
    end
    
    
    return result
  end

  def self.user_roll(notation)
    if /\d+d[\df%]+(?:\s*[+-]\s*\d+)?/.match(notation)
      roll = Actions.roll_dice(notation)
      return "#{roll[0]} #{roll[1]}"
    else
      return "BAD NOTATION"
    end
  end

  def self.quit
    exit
  end

 end


class Creature
  attr_reader :macros
  
  # Initializes a Creature.
  #
  # name - A String that will be set as the creature's name, and displayed as
  #        part of actions rolled.
  # info - An Array of ability scores, actions, and other nessisary data.
  def initialize(name, info)
    @name   = name
    @macros = { }
    
    info["actions"].each do |name, info|
      @macros[name.downcase] = lambda do |advantage = nil|
        roll = Actions.roll_dice(info[1])
        return "#{@name} uses #{name}\n"\
          "#{Actions.hit(info[0], advantage)}\n"\
          "#{roll[0]} #{info[2]} damage #{roll[1]}"
      end
    end
    
    info.each do |key, value|
      case key
      when "str", "dex", "con", "int", "wis", "cha"
        @macros["roll " + key] = lambda do |junk|
          roll = Actions.roll_dice("1d20 + #{(value - 10) / 2}")
          return "#{@name} rolls #{key.upcase}\n"\
            "#{roll[0]} #{roll[1]}"
        end
      end
    end
    
    @macros["roll initiative"] = lambda do |junk|
      roll = Actions.roll_dice("1d20 + #{(info["dex"] - 10) / 2}")
      return "#{@name} rolls Initiative\n"\
        "#{roll[0]} #{roll[1]}"
    end
  end
end


class Main

  def initialize
      @creatures = { }
      file = File.read("macros.json")
      file_hash = JSON.parse(file)

      file_hash.each do |name, info|
        @creatures[name.downcase] = Creature.new(name, info)
      end

      @macros = {
        "roll"  => lambda { |notation| Actions.user_roll(notation) },
        # "again" => lambda { |junk| Actions.again}
        "quit"  => lambda { |junk| quit(junk) }
      }
    end

  def run
    while true do
      print " > "
      command = gets.rstrip!.downcase
      action, remainder = Main.get_phrase(command, @macros.keys)
      action = @macros[action]
      if action
        display(action.call(remainder))
      else
        creature, remainder = Main.get_phrase(command, @creatures.keys)
        creature = @creatures[creature]
        if creature
          action, remainder = Main.get_phrase(remainder, creature.macros.keys)
          action = creature.macros[action]
          if action
            display(action.call(remainder))
          end
        end
      end
      puts
    end
  end

  def run
    loop do
      print ">"
      command(gets.chomp.downcase)
    end
  end

  def command(token)
    case token
    when "quit", "exit"
      exit
    end
  end

  def display(text)
    file = File.new("log.txt", "a")
    file.write("#{text} \n\n")
    file.close
    puts text
  end

  # Does more magic than you can comprehend. Shits out the phrase that you
  #   actually meant to type.
  #
  # command - A String that will be parsed.
  # phrases - An Array of Strings that the command will be checked against.
  #
  # Examples
  #
  #   check("fo baz", ["foo bar"])
  #   # => ["foo bar", "baz"]
  #
  #   check("d roll 1d6", ["dragon knight", "priest"])
  #   # => ["dragon knight", "roll 1d6"]
  #
  # Returns an Array with two items; either a String of the matched phrase or an
  #   empty String if no conclusive match is found, and a String of the
  #   unmatched remainder of the command.

  def self.get_phrase(command, phrases)
    result = [""]
    tmp = []
    phrases.each do |phrase|
      tmp.push(phrase.split)
    end

    # I have no idea how this line works
    rotated = Array.new(tmp.map(&:length).max){|i| tmp.map{|e| e[i]}}

    rotated.each do |phrase|
      candidate = nil
      candidate_count = 0

      phrase.each do |phrase_word|
        command_word = command.split[rotated.index(phrase)]

        if phrase_word and command_word
          if phrase_word.start_with?(command_word)
            if candidate != phrase_word
              candidate = phrase_word
              candidate_count += 1
            end
          end
        end
      end

      if candidate_count == 1
        result[0] += candidate + " "
      end
    end

    result[0].rstrip!
    result.push(command.split[result[0].split.length..-1].join(" "))

    if not phrases.include?(result[0])
      candidate = nil
      candidate_count = 0

      phrases.each do |phrase|
        if phrase.start_with?(result[0])
          candidate = phrase
          candidate_count += 1
        end
      end

      if candidate_count == 1
        result[0] = candidate
      else
        result[0] = ""
        result[1] = command
      end
    end

    return result
  end

  def quit(junk)
    exit
  end

end


# Main.new.run


class Main

  def initialize
    @output_buffer = ""
    @input_buffer = ""
    @running = true
    @curs_pos = 0 ## used for String.insert
    @keys = {
      :tab => 9,
      :enter => 10,
      :ctrl_w => 23,
      :backspace => 263,
      :left_arrow => 260,
      :right_arrow => 261,
      :normal_letters =>
        "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./'`"\
        "~!@\#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>? ".split("")
    }

    begin
      Curses.init_screen
      # Curses.curs_set(0) ## Invisible cursor
      Curses.noecho ## Don't display pressed characters
      term_w = Curses.cols - 1
      term_h = Curses.lines - 1
      @input_window = Curses::Window.new(1, term_w, term_h, 0)
      @input_window.keypad = true
      @output_window = Curses::Window.new(term_h - 1, term_w, 0, 0)
      draw_output("Testing.")
      @input_window.addstr(" > ")
      while @running
        handle_input(@input_window.getch)
      end
    ensure
      Curses.close_screen
    end
  end

  def handle_input(input)
    case input
    when @keys[:tab]
      draw_output(@keys[:normal_letters].inspect)
    when @keys[:ctrl_w]
      @running = false
    when @keys[:enter]
      draw_output(@input_buffer)
      @input_window.setpos(0, 3)
      @input_window.addstr(" " * @input_buffer.length)
      @input_window.setpos(0, 3)
      @input_buffer = ""
      @curs_pos = 0
    when @keys[:backspace]
      if @curs_pos > 0
        @input_window.setpos(0, 3 + (@input_buffer.length - 1))
        @input_window.addstr(" ")
        @input_window.setpos(0, 3 + (@input_buffer.length - 1))
        @input_buffer = @input_buffer[0..-2]
        @curs_pos -= 1
      end
    when @keys[:left_arrow]
      if @curs_pos > 0
        @curs_pos -= 1
        @input_window.setpos(0, @curs_pos + 3)
      end
    when @keys[:right_arrow]
      if @curs_pos < @input_buffer.length
        @curs_pos += 1
        @input_window.setpos(0, @curs_pos + 3)
      end
    else
      if @keys[:normal_letters].include?(input.to_s)
        @input_buffer.insert(@curs_pos, input.to_s)
        @input_window.setpos(0, 3)
        @input_window.addstr(@input_buffer)
        @curs_pos += 1
        @input_window.setpos(0, @curs_pos + 3)
        @input_window.refresh
      end
    end
  end

  def draw_output(string)
    string = string.scan(/.{1,#{@output_window.maxx-1}}/).join("\n")
    @output_buffer << string
    @output_buffer = @output_buffer.split("\n")
    if @output_buffer.length > @output_window.maxy
      delta = @output_buffer.length - @output_window.maxy
      @output_buffer = @output_buffer[delta..-1]
    end
    @output_buffer = @output_buffer.join("\n") + "\n"
    @output_window.setpos(0, 0)
    @output_window.addstr(@output_buffer)
    @output_window.refresh
    @input_window.refresh
  end

end


Main.new
