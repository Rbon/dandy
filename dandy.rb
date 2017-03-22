## TODO:  Spells.
##        Proper help text.
##        Smarter tab completion.

## BUGS: Un-numlock'd numberpad keys still insert text into the line editor.


require "json"
require "curses"


class Main

  def initialize
    @output_buffer = ""
    @input_buffer = ""
    @history = [""]
    @history_pos = 0
    @running = true
    @curs_pos = 0
    @keys = {
      :tab => 9,
      :enter => 10,
      :ctrl_w => 23,
      :down_arrow => 258,
      :up_arrow => 259,
      :backspace => 263,
      :left_arrow => 260,
      :right_arrow => 261,
      :delete => 330,
      :normal_keys =>
        "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./'`"\
        "~!@\#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>? ".split(""),
    }
    @usage = {
      "roll" =>
        "roll 1d4 2d6+3"
    }
    @commands = ["quit", "exit", "roll", "help"]

    begin
      Curses.init_screen
      # Curses.curs_set(0) ## Invisible cursor
      Curses.noecho ## Don't display pressed characters
      term_w = Curses.cols - 1
      term_h = Curses.lines - 1
      @input_window = Curses::Window.new(1, term_w, term_h, 0)
      @input_window.keypad = true
      @output_window = Curses::Window.new(term_h, term_w, 0, 0)
      @input_window.addstr(" > ")

      ## causes the screen to flicker once at boot so it doesn't flicker again
      @output_window.refresh
      @input_window.refresh

      while @running
        handle_input(@input_window.getch)
      end
    rescue Interrupt
    ensure
      Curses.close_screen
    end
  end

  def  handle_input(input)
    case input

    when @keys[:tab]
      current_word = @input_buffer.split(" ")[-1]
      if current_word
        @commands.each do |arg|
          if arg.start_with?(current_word)
            line = "#{@input_buffer.split(" ")[0..-2].join(" ")} #{arg} ".lstrip
            clear_line
            @input_window.addstr(line)
            @input_buffer = String.new(line)
            @curs_pos = @input_buffer.length
            @input_window.refresh
          end
        end
      end

    when @keys[:enter]
      if @input_buffer.length != 0
        draw_output(" > #{@input_buffer}")
        clear_line
        if @history.include?(@input_buffer)
          @history.delete(@input_buffer)
        end
        @history.insert(1, @input_buffer)
        run_command(@input_buffer)
        @input_buffer = ""
        @curs_pos = 0
        @history_pos = 0
      end

    when @keys[:backspace]
      if @curs_pos > 0
        @curs_pos -= 1
        remove_character(@curs_pos)
        @input_window.refresh
      end

    when @keys[:delete]
      if @curs_pos < @input_buffer.length
        remove_character(@curs_pos)
        @input_window.refresh
        @input_window.refresh
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

    when @keys[:up_arrow]
      if @history_pos == @history.length - 1
        access_history(0)
      else
        access_history(@history_pos + 1)
      end

    when @keys[:down_arrow]
      if @history_pos == 0
        access_history(@history.length - 1)
      else
        access_history(@history_pos - 1)
      end

    else
      if @keys[:normal_keys].include?(input.to_s)
        @input_buffer.insert(@curs_pos, input.to_s)
        @input_window.setpos(0, 3)
        @input_window.addstr(@input_buffer)
        @curs_pos += 1
        @input_window.setpos(0, @curs_pos + 3)
        @input_window.refresh
      else
        draw_output(input.to_s)
      end
    end
  end

  def access_history(position)
    @history_pos = position
    clear_line
    @input_window.addstr(@history[@history_pos])
    @input_buffer = String.new(@history[@history_pos])
    @curs_pos = @input_buffer.length
  end

  def clear_line
    @input_window.setpos(0, 3)
    @input_window.addstr(" " * @input_buffer.length)
    @input_window.setpos(0, 3)
  end

  def remove_character(position)
    @input_buffer.slice!(position)
    @input_window.setpos(0, 3)
    @input_window.addstr("#{@input_buffer} ")
    @input_window.setpos(0, position + 3)
  end

  def draw_output(string)
    string = string.scan(/.{1,#{@output_window.maxx-1}}/).join("\n")
    @output_buffer << string
    @output_buffer = @output_buffer.split("\n")
    if @output_buffer.length > @output_window.maxy
      delta = @output_buffer.length - @output_window.maxy
      @output_buffer = @output_buffer[delta..-1]
    end
    if @output_buffer.length < @output_window.maxy
      delta = @output_window.maxy - @output_buffer.length
      @output_window.setpos(delta, 0)
    else
      @output_window.setpos(0, 0)
    end
    @output_buffer = @output_buffer.join("\n") + "\n"
    @output_window.addstr(@output_buffer)
    @output_window.refresh
    @input_window.refresh
  end

  def run_command(line)
    @args = line.split(" ", -1)
    success = true
    case @args[0]

    when "exit", "quit"
      @running = false

    when "roll"
      if @args[1]
        bad_arg = false
        rolls = []

        ## check if all the args are proper notation
        @args[1..-1].each do |arg|
          match = arg.scan(/^(\d+d\d+)([-\+]?\d+)?$/)[0] ## dice notation
          if match
            rolls.push(match)
          else
            bad_arg = true
            break
          end
        end
        if bad_arg
          display_usage

        else
          rolls.each do |roll|
            count, sides = roll[0].split("d").map { |item| item.to_i }
            results, sum = roll_dice(count, sides)
            output = " | #{results.inspect}"
            if roll[1]
              modifier = roll[1].to_i
              if modifier > 0
                output << " +#{modifier}"
              elsif modifier < 0
                output << " #{modifier}"
              end
              sum += modifier
            end
            draw_output(sum.to_s + output)
          end
        end

      else
        display_usage
      end

    when "help"
      draw_output("Under construction.")

    else
      draw_output("No such command: #{@args[0]}")
    end

    draw_output(" ")
  end

  def roll_dice(count, sides)
    results = []
    count.times { results.push(rand(1..sides)) }
    return results, results.sum
  end

  def display_usage
    draw_output(
      "Example: #{@usage[@args[0]]}\n"\
      "Run help #{@args[0]} for more info."
    )
  end

end


Main.new


# class Actions

  # # Rolls to hit, i.e. 1d20 + attack mod.
  # #   Automatically re-results for crits and fumbles.
  # #
  # # attack_mod - An Integer of the total attack modifier for the action being
  # #              performed.
  # #
  # # Example
  # #
  # #   hit(2)
  # #   # => 16 to hit [14 + 2]
  # #
  # # Returns a multiple-line String detailing how the roll went.
  # def self.hit(attack_mod, advantage = nil)
    # result = ""
    # roll = roll_dice("1d20 + #{attack_mod}")
    # result += "#{roll[0]} to hit #{roll[1]}"

    # if roll[0] == 20 + attack_mod
      # result += "\nRolling to confirm crit...\n"
      # result += hit(attack_mod)

    # elsif roll[0] == 1 + attack_mod
      # result += "\nRolling to confirm fumble...\n"
      # result += hit(attack_mod)
    # end

    # if advantage
      # advantage = Main.get_phrase(advantage, ["advantage", "disadvantage"])[0]
      # case advantage
      # when "advantage"
        # result += "\nRolling for advantage...\n"
        # result += hit(attack_mod)
      # when "disadvantage"
        # result += "\nRolling for disadvantage...\n"
        # result += hit(attack_mod)
      # end
    # end


    # return result
  # end

  # def self.user_roll(notation)
    # if /\d+d[\df%]+(?:\s*[+-]\s*\d+)?/.match(notation)
      # roll = Actions.roll_dice(notation)
      # return "#{roll[0]} #{roll[1]}"
    # else
      # return "BAD NOTATION"
    # end
  # end

  # def self.quit
    # exit
  # end

# end

# class Creature
  # attr_reader :macros

  # # Initialize s a Creature.
  # #
  # # name - A String that will be set as the creature's name, and displayed as
  # #        part of actions rolled.
  # # info - An Array of ability scores, actions, and other nessisary data.
  # def initi alize(name, info)
    # @name   = name
    # @macros = { }

    # info[" actions"].each do |name, info|
      # @macros[name.downcase] = lambda do |advantage = nil|
        # roll = Actions.roll_dice(info[1])
        # return "#{@name} uses #{name}\n"\
          # "#{Actions.hit(info[0], advantage)}\n"\
          # "#{roll[0]} #{info[2]} damage #{roll[1]}"
      # end
    # end

    # info.each do |key, value|
      # case key
      # when "str", "dex", "con", "int", "wis", "cha"
        # @macros["roll " + key] = lambda do |junk|
          # roll = Actions.roll_dice("1d20 + #{(value - 10) / 2}")
          # return "#{@name} results #{key.upcase}\n"\
            # "#{roll[0]} #{roll[1]}"
        # end
      # end
    # end

    # @macros["roll initiative"] = lambda do |junk|
      # roll = Actions.roll_dice("1d20 + #{(info["dex"] - 10) / 2}")
      # return "#{@name} results Initiative\n"\
        # "#{roll[0]} #{roll[1]}"
    # end
  # end
# end
