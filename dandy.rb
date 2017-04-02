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

module Keys
  NORMAL_KEYS =
    "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./'`"\
    "~!@\#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>? ".split("")
  SPECIAL_KEYS = {
    tab: 9,
    enter: 10,
    down_arrow: 258,
    up_arrow: 259,
    left_arrow: 260,
    right_arrow: 261,
    home_key: 262,
    backspace: 263,
    delete: 330,
    end_key: 360
  }.invert

  def tab
    current_word = @input_buffer.split(" ")[-1]
    return unless current_word
    @commands.each do |arg|
      next unless arg.start_with?(current_word)
      line = "#{@input_buffer.split(" ")[0..-2].join(" ")} #{arg} ".lstrip
      clear_line
      @input_window.addstr(line)
      @input_buffer = String.new(line)
      @curs_pos = @input_buffer.length
      @input_window.refresh
    end
  end

  def enter
    return if @input_buffer.empty?
    draw_output(" > #{@input_buffer}")
    clear_line
    @history.delete(@input_buffer) if @history.include?(@input_buffer)
    @history.insert(1, String.new(@input_buffer))
    draw_output(run_command(@input_buffer).to_s)
    draw_output(" ")
    @input_buffer = ""
    @curs_pos = 0
    @history_pos = 0
  end

  def backspace
    return if @curs_pos.zero?
    @curs_pos -= 1
    remove_character(@curs_pos)
    @input_window.refresh
  end

  def delete
    return unless @curs_pos < @input_buffer.length
    remove_character(@curs_pos)
    @input_window.refresh
    @input_window.refresh
  end

  def left_arrow
    return if @curs_pos.zero?
    @curs_pos -= 1
    @input_window.setpos(0, @curs_pos + 3)
  end

  def right_arrow
    return unless @curs_pos < @input_buffer.length
    @curs_pos += 1
    @input_window.setpos(0, @curs_pos + 3)
  end

  def up_arrow
    if @history_pos == @history.length - 1
      access_history(0)
    else
      access_history(@history_pos + 1)
    end
  end

  def down_arrow
    if @history_pos.zero?
      access_history(@history.length - 1)
    else
      access_history(@history_pos - 1)
    end
  end

  def home_key
    @input_window.setpos(0, 3)
    @curs_pos = 0
  end

  def end_key
    @input_window.setpos(0, 3 + @input_buffer.length)
    @curs_pos = @input_buffer.length
  end
end


module Builtins
  def make_alias(args)
    debug_output("alias: got args: #{args}")
    return "alias: bad syntax" unless args
    name, command = args.split(" ", 2)
    @aliases[name] = command
    "Alias \"#{name}\" set as: #{command}"
  end

  def echo(args)
    # @builtins.expand_line(args)
    args
  end

  def roll(args)
    return unless args
    debug_output("roll: got line: #{args}")
    args.match(/^(\d+)d(\d+)([-\+]\d+)?$/) do |notation|
      results = []
      count, sides, mod = notation.captures
      count.to_i.times { results.push(rand(1..sides.to_i)) }
      return "#{results.sum + mod.to_i} (#{count}d#{sides}#{mod})"
    end
    "roll: bad syntax"
  end

  def halt
    @running = false
  end

  def exec(file)
    return "exec: no file given" unless file
    return "exec: no such file #{file}" unless File.exist?(file)
    draw_output("Executing file: #{file}")
    File.readlines(file).each { |line| run_command(line) }
    draw_output("Done")
  end
end

class Main
  include Builtins
  include Keys
  attr_reader :aliases, :input_window, :draw_output
  attr_writer :running

  def initialize
    @input_buffer = ""
    @history = [""]
    @history_pos = 0
    @curs_pos = 0
    @commands = %w(quit exit roll help)
    @output_buffer = ""
    @aliases = {}
    @running = true
    # @debug = true
  end

  def run_command(line)
    # debug_output("run_command: got line: #{line}")
    @args = line.split(" ", 2)
    if @aliases[@args[0]]
      return run_command(@aliases[@args[0]])
    end
    case @args[0]
    when /^((?:\d+d\d+)(?:[-\+]\d+)?)$/ then roll(line)
    when "alias" then make_alias(@args[1])
    when "exec" then exec(@args[1])
    when "roll" then roll(@args[1])
    when "echo" then echo(@args[1])
    when "exit", "quit"
      halt
    else "No such command: #{@args[0].inspect}"
    end
  end

  def run
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
    exec("config")
    draw_output(" ")
    @silent = false
    handle_input(@input_window.getch) while @running
  rescue Interrupt
  ensure
    Curses.close_screen
  end

  def draw_output(string)
    return if @silent
    string = string.scan(/.{1,#{@output_window.maxx - 1}}/).join("\n")
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

  def handle_input(input)
    if SPECIAL_KEYS[input]
      method(SPECIAL_KEYS[input]).call
    else
      type_character(input.to_s)
    end
  end

  def type_character(input)
    if NORMAL_KEYS.include?(input)
      @input_buffer.insert(@curs_pos, input)
      @input_window.setpos(0, 3)
      @input_window.addstr(@input_buffer)
      @curs_pos += 1
      @input_window.setpos(0, @curs_pos + 3)
      @input_window.refresh
    else
      draw_output(input)
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

  # def expand_line(line)
    # new_line = []
    # line.split(" ").each do |word|
      # if word.match?(/\([^\(\)]*\)/)
        # debug_output("expand_line: got parens match")
        # new_word = run_command(word[1..-2])
        # new_line.push(new_word)
      # else
        # new_line.push(word)
      # end
    # end
    # line = new_line.join(" ")
  # end
end


Main.new.run
