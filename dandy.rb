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
##
## Text can be typed off screen, if the line is long enough. I don't know what
## the expected result should be, but I don't like it as it is.

require "json"
require "curses"

class InputHandler
  SPECIAL_KEYS = {
    tab:         9,
    enter:       10,
    down_arrow:  258,
    up_arrow:    259,
    left_arrow:  260,
    right_arrow: 261,
    home_key:    262,
    backspace:   263,
    delete:      330,
    end_key:     360
  }.invert
  BINDINGS = {
    tab:         :under_construction,
    enter:       :return,
    backspace:   :left_delete_character,
    delete:      :delete_character,
    left_arrow:  :move_cursor_left,
    right_arrow: :move_cursor_right,
    up_arrow:    :shift_history_up,
    down_arrow:  :shift_history_down,
    home_key:    :start_of_line,
    end_key:     :end_of_line
  }.freeze

  def self.handle_input(input)
    BINDINGS[SPECIAL_KEYS[input]] || :type_character
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
    @pos = (@pos + 1) % @history.length
  end

  def shift_down
    @pos = (@pos - 1) % @history.length
  end

  def current
    @history[@pos]
  end
end

class Cursor
  attr_reader :pos

  def initialize(box)
    @box = box
    @pos = 0
  end

  def move_right(distance = 1)
    self.pos = @pos + distance
  end

  def move_left(distance = 1)
    self.pos = @pos - distance
  end

  def pos=(new_pos)
    new_pos = [[0, new_pos].max, @box.buffer.length].min ## keep in bounds
    @pos = new_pos
    @box.window.setpos(0, new_pos + 3)
  end
end

class Main
  attr_reader :aliases, :input_window, :draw_output, :input, :output, :silent
  attr_writer :running

  def initialize
    @commands = %w(quit exit roll help)
    @aliases = {}
    @running = true
    # @debug = true
    Curses.init_screen
    # Curses.curs_set(0) ## Invisible cursor
    Curses.noecho ## Don't display pressed characters
    @input_box = InputBox.new(self)
    @output_box = @input_box.output
    # @output.silent = true
    # exec("config")
    # @output.draw(" ")
    # @output.silent = false

    ## causes the screen to flicker once at boot so it doesn't flicker again
    @output_box.window.refresh
    @input_box.window.refresh
  end

  def run
    while @running
      @input = @input_box.window.getch
      @input_box.method(InputHandler.handle_input(@input)).call
      @output_box.window.refresh
      @input_box.window.refresh
    end
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
  attr_reader :window, :output, :cursor
  attr_accessor :buffer, :history

  def initialize(core)
    @core = core
    term_w = Curses.cols - 1
    term_h = Curses.lines - 1
    @window = Curses::Window.new(1, term_w, term_h, 0)
    @history = History.new
    @output = Output.new(self)
    @cursor = Cursor.new(self)
    @window.keypad = true
    @window.addstr(" > ")
    @buffer = ""
  end

  def delete_character(offset = 0)
    @buffer.slice!(@cursor.pos + offset)
    @window.setpos(0, 3)
    @window.addstr("#{buffer} ")
    @cursor.pos = @cursor.pos + offset
  end

  def left_delete_character
    delete_character(-1) if @cursor.pos > 0
  end

  def move_cursor_left
    @cursor.move_left
  end

  def move_cursor_right
    @cursor.move_right
  end

  def clear_line
    @window.setpos(0, 3)
    @window.addstr(" " * @buffer.length)
    @window.setpos(0, 3)
  end

  def type_character
    @buffer.insert(@cursor.pos, @core.input.to_s)
    @window.setpos(0, 3)
    @window.addstr(@buffer)
    @cursor.move_right(@core.input.to_s.length)
  end

  def shift_history_up
    shift_history(:up)
  end

  def shift_history_down
    shift_history(:down)
  end

  def shift_history(direction)
    @history.method("shift_#{direction}").call
    clear_line
    @window.addstr(@history.current)
    @buffer = String.new(@history.current)
    @cursor.pos = @buffer.length
  end

  def start_of_line
    @cursor.pos = 0
  end

  def end_of_line ## line ends HERE
    @cursor.pos = @buffer.length
  end

  def return
    return if @buffer.empty?
    @output.draw(" > #{@buffer}")
    clear_line
    @history.add(@buffer)
    @output.draw(Commands.new(@output).run(@buffer).to_s)
    @output.draw(" ")
    @buffer = ""
    @cursor.pos = 0
  end

  def under_construction
    @output.draw("The key you have pressed in currently under construction.")
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
  end

  def debug(string)
    draw_output(string) if @debug
  end
end

begin
  Main.new.run
rescue Interrupt
ensure
  Curses.close_screen
end
