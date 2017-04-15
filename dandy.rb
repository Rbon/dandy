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

require "curses"
require "yaml"

## Hanldes the input.
class Bindings
  attr_reader :keys, :bindings

  def initialize(core, prompt, output_box)
    @groups = {"core": core, "prompt": prompt, "output_box": output_box}
    @keys = YAML.load(File.read("keys.yaml"))[0].invert
    @bindings = YAML.load(File.read("bindings.yaml"))[0]
  end

  def handle_input(input)
    group, action = @bindings[@keys[input]] || [:prompt, "type_key"]
    # @groups[:output_box].draw("#{@groups[group.to_sym]}, #{action.inspect}")
    @groups[group.to_sym].method(action).call
  end
end

# A generic command history class with methods to manage itself.
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

# The cursor for the command prompt.
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
    @box.setpos(0, new_pos + 3)
  end
end

# The class that contains the main loop.
class Main
  attr_reader :aliases, :input_window, :draw_output, :input, :output, :silent
  attr_writer :running

  def initialize
    @commands = %w[quit exit roll help]
    @aliases = {}
    @running = true
    # @debug = true
    Curses.init_screen
    # Curses.curs_set(0) ## Invisible cursor
    Curses.noecho ## Don't display pressed characters
    Curses.raw ## Passes interruupts, etc. through to the program.
    @input_box = InputBox.new(self)
    @output_box = @input_box.output
    @bindings = Bindings.new(self, @input_box, @output_box)
    # @output.silent = true
    # exec("config")
    # @output.draw(" ")
    # @output.silent = false

    ## causes the screen to flicker once at boot so it doesn't flicker again
    @output_box.refresh
    @input_box.refresh
  end

  def run
    while @running
      @input = @input_box.getch
      @bindings.handle_input(@input)
      @output_box.refresh
      @input_box.refresh
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

# Methods that are the built-in commands for dandy.
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

# Extends the Curses::Window class to add some more stuff.
class Box < Curses::Window
  def initialize(height, width, top, left)
    super
    @max_w = maxx
    @max_h = maxy
  end
end

# The command prompt at the bottom of the screen.
class InputBox < Box
  attr_reader :window, :output, :cursor
  attr_accessor :buffer, :history

  def initialize(core)
    super(1, Curses.cols - 1, Curses.lines - 1, 0)
    @core = core
    @history = History.new
    @output = OutputBox.new
    @prompt = " > "
    @cursor = Cursor.new(self)
    @buffer = ""
    @line_start = @prompt.length
    self.keypad = true
    addstr(@prompt)
  end

  def delete_character(offset = 0)
    @buffer.slice!(@cursor.pos + offset)
    draw("#{@buffer} ")
    @cursor.pos += offset
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
    setpos(0, @prompt.length)
    addstr(" " * @buffer.length)
    setpos(0, @prompt.length)
  end

  def type_key(key = @core.input.to_s)
    @buffer.insert(@cursor.pos, key)
    draw(@buffer)
    @cursor.pos += key.length
  end

  def draw(str)
    clear_line
    addstr(str)
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
    draw(@history.current)
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
    pos = 0
    clear_line
    @history.add(@buffer)
    @output.draw(Commands.new(@output).run(@buffer).to_s)
    @output.draw(" ")
    @buffer = ""
    @cursor.pos = 0
  end

  def halt
    @core.running = false
  end

  def test
    @output.draw(Curses::Key::LEFT)
  end
end

# The section of the screen where output is drawn.
class OutputBox < Box
  attr_reader :window
  attr_writer :silent

  def initialize
    super(Curses.lines - 1, Curses.cols + 1, 0, 0)
    @silent = false
    @buffer = []
  end

  def draw(string)
    string.scan(/.{1,#{@max_w - 1}}/).map do |line|
      @buffer << line.ljust(@max_w - 1, " ")
    end
    line_count = @buffer.length
    @buffer.slice!(0, [line_count - @max_h, 0].max)
    output(@buffer.join("\n"), [@max_h - line_count, 0].max)
  end

  def debug(string)
    draw_output(string) if @debug
  end

  def output(string, v_pos)
    setpos(v_pos, 0)
    addstr(string)
  end
end

begin
  Main.new.run
ensure
  Curses.close_screen
end
