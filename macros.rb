##
# TODO: crits

require "json"

# Methods that allow for dice rolls, with common roll types having their own
#   methods.
class Macros
  attr_reader :creatures
  
  def initialize
    @creatures = { }
    file = File.read("macros.json")
    file_hash = JSON.parse(file)
    
    file_hash.each do |name, info|
      @creatures[name] = Creature.new(name, info)
    end
  end
  
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
  def roll(notation)
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
  
  # Rolls to hit, i.e. 1d20 + ability mod.
  #
  # attack_mod - An Integer of the total attack modifier for the action being
  #              performed.
  #
  # Example
  #
  #   hit(2)
  #   # => 16 to hit [14 + 2]
  #
  # Returns a String detailing how the roll went.
  def hit(attack_mod)
    result = rand(1..20)
    return "#{result + attack_mod} to hit ([#{result}] + #{attack_mod})"
    
    # if result == 20
    #   crit_roll = hit
    # end
  end
  
  def attack(action)
    result = roll(action[1])
    return "#{hit(action[0])}\n"\
           "#{result[0]} #{action[2]} damage #{result[1]}"
  end
  
end

# A character sheet, basically. Contains no methods that are useful for
#   anything but setting initial values.
class Creature
  attr_reader :str_mod, :dex_mod, :con_mod, :int_mod, :wis_mod, :cha_mod,
              :actions, :name
              
  # Initialize a Creature
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
    @actions = actions
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

class Main
  def initialize
    @macros = Macros.new
  end
  
  def run
    while true do
      print " > "
      command = gets.chomp.downcase
      
      if command == "quit"
        exit
      else
        puts check(command, @macros.creatures.keys)
      end
    end
  end
  
  def check(string, list, depth = 0)
    matches = 0
    result = nil
    
    list.each do |item|
      if item.start_with?(string.split[0..depth].join(" "))
        result = item
        matches += 1
      end
    end
    
    if matches == 0
      return "NO MATCH"
    elsif matches == 1
      return result
    else
      
      if string.split.length == 1
        return "NO MATCH"
      else
        return check(string, list, (depth + 1))
      end
    end
  end
end

macros = Macros.new
puts "#{macros.roll("4d8")}"
# Main.new.run
