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

end

class InputHandler
  include Keys

  def initialize(input, output)
    @input = input
    @output = output
  end

  def handle_input
    input = @input.window.getch
    if SPECIAL_KEYS[input]
      method(SPECIAL_KEYS[input]).call
    else
      @input.type_character(input.to_s)
    end
  end

  def tab
    current_word = @buffer.split(" ")[-1]
    return unless current_word
    @commands.each do |arg|
      next unless arg.start_with?(current_word)
      line = "#{@input.buffer.split(" ")[0..-2].join(" ")} #{arg} ".lstrip
      @input.clear_line
      @input.window.addstr(line)
      @input.buffer = String.new(line)
      @input.curs_pos = @input.buffer.length
      @input.window.refresh
    end
  end

  def enter
    return if @input.buffer.empty?
    @output.draw(" > #{@input.buffer}")
    @input.clear_line
    @input.history.add(@input.buffer)
    @output.draw(Commands.new(@output).run(@input.buffer).to_s)
    @output.draw(" ")
    @input.buffer = ""
    @input.curs_pos = 0
    @input.history_pos = 0
  end

  def backspace
    return if @input.curs_pos.zero?
    @input.curs_pos -= 1
    @input.remove_character(@input.curs_pos)
    @input.window.refresh
  end

  def delete
    return unless @curs_pos < @buffer.length
    remove_character(@curs_pos)
    @window.refresh
    @window.refresh
  end

  def left_arrow
    return if @curs_pos.zero?
    @curs_pos -= 1
    @window.setpos(0, @curs_pos + 3)
  end

  def right_arrow
    return unless @curs_pos < @buffer.length
    @curs_pos += 1
    @window.setpos(0, @curs_pos + 3)
  end

  # def up_arrow
    # if @history_pos == @history.length - 1
      # access_history(0)
    # else
      # access_history(@history_pos + 1)
    # end
  # end

  def up_arrow
    @input.prev_history
  end

  def down_arrow
    @input.next_history
  end

  def home_key
    @input.window.setpos(0, 3)
    @curs_pos = 0
  end

  def end_key
    @input.window.setpos(0, 3 + @input.buffer.length)
    @curs_pos = @input.buffer.length
  end
end

class History
  def initialize
    @history = [""]
    @pos = 0
  end

  def add(input)
    @history.delete(input)
    @history.insert(1, String.new(input))
    @pos = 0
  end

  def shift_up
    @pos = (@pos + 1) % (@history.length)
  end

  def shift_down
    @pos = (@pos - 1) % (@history.length)
  end

  def current
    @history[@pos]
  end
end

class Main
  include Keys

  attr_reader :aliases, :input_window, :draw_output, :input, :output, :silent
  attr_writer :running

  def initialize
    @commands = %w(quit exit roll help)
    @aliases = {}
    @running = true
    # @debug = true
  end

  def run
    Curses.init_screen
    # Curses.curs_set(0) ## Invisible cursor
    Curses.noecho ## Don't display pressed characters
    @input_box = InputBox.new(self)
    @output = @input_box.output
    # @output.silent = true
    # exec("config")
    # @output.draw(" ")
    # @output.silent = false
    ## causes the screen to flicker once at boot so it doesn't flicker again
    @output.window.refresh
    @input_box.window.refresh

    InputHandler.new(@input_box, @output).handle_input while @running
  rescue Interrupt
  ensure
    Curses.close_screen
  end

  def expand_line(line)
    new_line = []
    line.split(" ").each do |word|
      if word.match?(/\([^\(\)]*\)/)
        @output.debug("expand_line: got parens match")
        new_word = run_command(word[1..-2])
        new_line.push(new_word)
      else
        new_line.push(word)
      end
    end
    new_line.join(" ")
  end
end

class Commands
  COMMAND_LIST = {
    alias: :make_alias,
    echo: :echo,
    roll: :roll,
    halt: :halt,
    quit: :halt,
    exit: :halt,
    exec: :exec
  }.freeze

  def initialize(output)
    @output = output
  end

  def run(line)
    return unless line
    command, args = line.split(" ", 2)
    if COMMAND_LIST[command.to_sym]
      method(COMMAND_LIST[command.to_sym]).call(args)
    else
      "No such command: #{command}"
    end
  end

  def make_alias(args)
    @output.debug("alias: got args: #{args}")
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
    # @output.debug("roll: got line: #{args}")
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
    @output.draw("Executing file: #{file}")
    File.readlines(file).each { |line| run_command(line) }
    @output.draw("Done")
  end
end

class InputBox
  include Keys

  attr_reader :window, :output
  attr_accessor :buffer, :curs_pos, :history, :history_pos

  def initialize(core)
    @history = History.new
    @core = core
    @curs_pos = 0
    term_w = Curses.cols - 1
    term_h = Curses.lines - 1
    @window = Curses::Window.new(1, term_w, term_h, 0)
    @output = Output.new(self)
    @window.keypad = true
    @window.addstr(" > ")
    @buffer = ""
  end

  def remove_character(position)
    @buffer.slice!(position)
    @window.setpos(0, 3)
    @window.addstr("#{buffer} ")
    @window.setpos(0, position + 3)
  end

  def clear_line
    @window.setpos(0, 3)
    @window.addstr(" " * @buffer.length)
    @window.setpos(0, 3)
    @window.refresh
  end

  def type_character(input)
    if NORMAL_KEYS.include?(input)
      @buffer.insert(@curs_pos, input)
      @window.setpos(0, 3)
      @window.addstr(@buffer)
      @curs_pos += 1
      @window.setpos(0, @curs_pos + 3)
      @window.refresh
    else
      @output.draw(input)
    end
  end

  def prev_history
    shift_history(:up)
  end

  def next_history
    shift_history(:down)
  end

  def shift_history(direction)
    @history.method("shift_#{direction}").call
    clear_line
    @window.addstr(@history.current)
    @buffer = String.new(@history.current)
    @curs_pos = @buffer.length
  end
end

class Output
  attr_reader :window
  attr_writer :silent

  def initialize(input)
    term_w = Curses.cols - 1
    term_h = Curses.lines - 1
    @input = input
    @window = Curses::Window.new(term_h, term_w, 0, 0)
    @buffer = ""
    @silent = false
  end

  def draw(string)
    return if @silent
    string = string.scan(/.{1,#{@window.maxx - 1}}/).join("\n")
    @buffer << string
    @buffer = @buffer.split("\n")
    if @buffer.length > @window.maxy
      delta = @buffer.length - @window.maxy
      @buffer = @buffer[delta..-1]
    end
    if @buffer.length < @window.maxy
      delta = @window.maxy - @buffer.length
      @window.setpos(delta, 0)
    else
      @window.setpos(0, 0)
    end
    @buffer = @buffer.join("\n") + "\n"
    @window.addstr(@buffer)
    @window.refresh
    @input.window.refresh
  end

  def debug(string)
    draw_output(string) if @debug
  end
end

Main.new.run
