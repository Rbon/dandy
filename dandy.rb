## TODO:
## Spells.
##
## Proper help text.
##
## Smarter tab completion.

## BUGS:
## Un-numlock'd numberpad keys still insert text into the line editor.
##
## Backspace acts differently on other computers.
##
## Syntax errors in sub-commands compound with the same errors in the
## super-command.


require "json"
require "curses"


class Main
  attr_writer(:running)

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
      :home => 262,
      :delete => 330,
      :end => 360,
      :normal_keys =>
        "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./'`"\
        "~!@\#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>? ".split(""),
    }
    @usage = {
      "roll" =>
        "roll 1d4 2d6+3"
    }
    @commands = ["quit", "exit", "roll", "help"]
    @aliases = {"attack" => "roll 1d20"}
    @builtins = Builtins.new(self)

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

  def handle_input(input)
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
        @history.insert(1, String.new(@input_buffer))
        draw_output(run_command(@input_buffer).to_s)
        draw_output(" ")
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

    when @keys[:home]
      @input_window.setpos(0, 3)
      @curs_pos = 0

    when @keys[:end]
      @input_window.setpos(0, 3 + @input_buffer.length)
      @curs_pos = @input_buffer.length

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

    ## expand sub-commands
    new_line = []
    line.split(" ").each do |word|
      if word.match?(/\([^\(\)]*\)/)
        new_line.push(run_command(word[1..-2]))
        next
      end
      new_line.push(word)
    end
    line = new_line.join(" ")

    ## quick roll
    if line.match?(/^((?:\d+d\d+)(?:[-\+]\d+)?)$/)
      return @builtins.roll(line)
    end

    @args = line.split(" ", 2)
    case @args[0]
    when "roll"
      return @builtins.roll(@args[1])
    when "echo"
      return @builtins.echo(@args[1])
    when "exit", "quit"
      return @builtins.quit
    else
      draw_output("No such command: #{@args[0].inspect}")
    end
  end

end


class Builtins

  def initialize(core)
    @core = core
  end

  def echo(args)
    return args
  end

  def roll(args)
    args.match(/^(\d+)d(\d+)([-\+]\d+)?$/) do |notation|
      results = []
      count, sides, mod = notation.captures
      count.to_i.times { results.push(rand(1..sides.to_i)) }
      notation = "#{count}d#{sides}#{mod.to_s}"
      return "#{results.sum + mod.to_i} (#{count}d#{sides}#{mod.to_s})"
    end
    return "roll: bad syntax"
  end

  def quit
    @core.running = false
  end

end


Main.new

