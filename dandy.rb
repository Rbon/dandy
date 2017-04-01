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
  attr_reader :aliases
  attr_writer :running

  def initialize
    @output_buffer = ""
    @input_buffer = ""
    @history = [""]
    @history_pos = 0
    @running = true
    @curs_pos = 0
    normal_keys =
        "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./'`"\
        "~!@\#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>? ".split("")
    @keys = {
      tab: 9,
      enter: 10,
      ctrl_w: 23,
      down_arrow: 258,
      up_arrow: 259,
      backspace: 263,
      left_arrow: 260,
      right_arrow: 261,
      home: 262,
      delete: 330,
      end: 360,
      normal_keys: normal_keys
    }
    @commands = ["quit", "exit", "roll", "help"]
    @aliases = {"attack" => "roll 1d20"}
    @builtins = Builtins.new(self)
    @debug = false
  end

  def run
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
      @silent = true
      @builtins.exec("config")
      @silent = false
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
    return if @silent
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

  def debug_output(string)
    draw_output(string) if @debug
  end

  def run_command(line)
    debug_output("run_command: got line: #{line}")
    @args = line.split(" ", 2)
    # return run_command(@aliases[@args[0]]) if @aliases[@args[0]]
    if @aliases[@args[0]]
      debug_output("run_command: got alias: #{@args[0]}")
      output = run_command(@aliases[@args[0]])
    end
    output =
      case @args[0]
      when /^((?:\d+d\d+)(?:[-\+]\d+)?)$/ then @builtins.roll(line)
      when "alias" then @builtins.alias(@args[1])
      when "exec" then @builtins.exec(@args[1])
      when "roll" then @builtins.roll(@args[1])
      when "echo" then @builtins.echo(@args[1])
      when "exit", "quit" then @builtins.quit
      else "No such command: #{@args[0].inspect}"
      end
    debug_output("run_command: output: #{output}")
    return output
  end

  def expand_line(line)
    new_line = []
    line.split(" ").each do |word|
      if word.match?(/\([^\(\)]*\)/)
        debug_output("expand_line: got parens match")
        new_word = run_command(word[1..-2])
        new_line.push(new_word)
      else
        new_line.push(word)
      end
    end
    line = new_line.join(" ")
  end
end

class Builtins
  def initialize(core)
    @core = core
  end

  def alias(args)
    @core.debug_output("alias: got args: #{args}")
    return "alias: bad syntax" unless args
    name, command = args.split(" ", 2)
    @core.aliases[name] = command
    return "Alias \"#{name}\" set as: #{command}"
  end

  def echo(args)
    return @core.expand_line(args)
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

  def exec(file)
    return "exec: no file given" unless file
    return "exec: no such file #{file}" unless File.exists?(file)
    @core.draw_output("Executing file: #{file}")
    File.readlines(file).each { |line| @core.run_command(line) }
    @core.draw_output("Done")
  end
end

Main.new.run

