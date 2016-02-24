##
# TODO: Support for varying string length for arrays searched using get_phrase.
#       Logging.
#       Hard-coded commands that don't require a creature as first phrase.

require "json"

# Methods that allow for dice rolls, with common roll types having their own
#   methods. All methods are module methods and should be called on the Macros
#   module.
class Macros

  # Makes a speudorandom dice roll of any arbitrary count and faces.
  #
  # notation - A dice notation, such as 1d6, as a String.
  #
  # Examples
  #
  #   roll("4d8")
  #   # => [13, [7, 2, 1, 3]]
  #
  # Returns an Array with two items--an Integer sum of the rolls, and an
  #   Array of the individual roll Integers.
  def self.roll(notation)
    notation = notation.split("d")
    dice     = []
    sum      = 0
    
    (1..notation[0].to_i).each do
      result = rand(1..notation[1].to_i)
      dice << result
      sum += result
    end
    
    return sum, dice
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
  def self.hit(attack_mod)
    result = ""
    roll = rand(1..20)
    result += "#{roll + attack_mod} to hit | [#{roll}] + #{attack_mod}"
    
    if roll == 20
      result += "\nRolling to confirm crit...\n"
      roll = rand(1..20)
      result += "#{roll + attack_mod} to hit | [#{roll}] + #{attack_mod}"
      
    elsif roll == 1
      result += "\nRolling to confirm fumble...\n"
      roll = rand(1..20)
      result += "#{roll + attack_mod} to hit | [#{roll}] + #{attack_mod}"
    end
      
    return result
    
    # if result == 20
    #   crit_roll = hit
    # end
  end
  
  def self.macro(creature, action)
    result = roll(action.info[1])
    return "#{creature.name} uses #{action.name}\n"\
           "#{hit(action.info[0])}\n"\
           "#{result[0]} #{action.info[2]} damage | #{result[1]}"
  end
end

# A character sheet, basically. Contains no methods that are useful for
#   anything but setting initial values.
class Creature
  attr_reader :str_mod, :dex_mod, :con_mod, :int_mod, :wis_mod, :cha_mod,
              :actions, :name
              
  # Initialize a Creature.
  #
  # name - A String that will be displayed as part of actions rolled.
  # info - An Array of Strings denoting ability scores, actions, and other
  #        nessisary data.
  def initialize(name, info)
    @name    = name
    @str     = info["str"]
    @dex     = info["dex"]
    @con     = info["con"]
    @int     = info["int"]
    @wis     = info["wis"]
    @cha     = info["cha"]
    @str_mod = mod(@str)
    @dex_mod = mod(@dex)
    @con_mod = mod(@con)
    @int_mod = mod(@int)
    @wis_mod = mod(@wis)
    @cha_mod = mod(@cha)
    @actions = { }
    
    info["actions"].each do |name, info|
      @actions[name.downcase] = Action.new(name, info)
    end
  end
  
  # Get an ability modifier.
  #
  # ability - The ability score as an Integer.
  #
  # Examples
  #
  #   mod(15)
  #   # => 2
  #
  # Returns the modifier as an Integer.
  def mod(ability)
    return (ability - 10) / 2
  end
end

# An action that a Creature can take.
class Action
  attr_reader :name, :info
  def initialize(name, info)
    @name = name
    @info = info
  end
end

# The class which contains the main loop, as well as other methods nessicary
#   for running the script.
class Main
  def initialize
      @creatures = { }
      file = File.read("macros.json")
      file_hash = JSON.parse(file)
      
      file_hash.each do |name, info|
        @creatures[name.downcase] = Creature.new(name, info)
      end
    end
  
  def run
    while true do
      print " > "
      command = gets.chomp.downcase
      
      if command == "quit"
        exit
        
      else
        first_pass = get_phrase(command, @creatures.keys)
        
        if first_pass.class == Array
          creature = @creatures[first_pass[0]]
          second_pass = get_phrase(first_pass[1], creature.actions.keys)
          
          if second_pass.class == Array
            action = creature.actions[second_pass[0]]
            puts Macros.macro(creature, action) + "\n\n"
          end
        end
      end
    end
  end
  
  # Determine if a String begins with any item in an Array of Strings.
  #   Auto-complete words. Does not ignore case.
  #
  # command - A String that will be parsed.
  # phrases - An Array of Strings that the command will be checked against.
  # depth   - An Integer of how many words at the start of the command should be
  #           checked. This number is automatically incremeneted as the method
  #           recurses, and should not be set manually.
  #
  # Examples
  #
  #   check("knight roll 1d6", ["knight", "priest"])
  #   # => ["knight", "roll 1d6"]
  #
  #   check("kni roll 1d6", ["knight", "priest"])
  #   # => ["knight", "roll 1d6"]
  #
  # Returns an Array containing the matching item, and the remainder of command
  #   if one match is found.
  #   Returns "NO MATCH" for 0 matches.
  #   Returns "TOO MANY MATCHES" for any number of matches greater than 1.
  def get_phrase(command, phrases, depth = 0)
    word = command.split[depth]
    matches = []
  
    phrases.each do |phrase|
      if phrase.split[depth..-1].join(" ").start_with?(word)
        matches << phrase
      end
    end
    
    if matches.length == 0
      return "NO MATCH"
      
    elsif matches.length == 1
      return matches * " ", command.split[depth + 1..-1].join(" ")
      
    else
      if command.split.length == 1 # avoids infinite recursion
        return "TOO MANY MATCHES"
      else
        return get_phrase(command, matches, depth + 1)
      end
    end
  end
end

Main.new.run
