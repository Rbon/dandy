# TODO:
#   Exclude unneeded modifiers in roll output.
#   Write a better description for get_phrase.
#   Combat advantage and disadvantage.
#   Rolls for init.
#   Better a la carte dicerolls.

require "json"

# Methods that allow for dice rolls, with common roll types having their own
#   methods. All methods are module methods and should be called on the Macros
#   module.
class Macros

  # Makes a speudorandom dice roll of any arbitrary count and faces.
  #
  # notation - the dice notation, as a String.
  #
  # Examples
  #
  #   roll("4d8")
  #   # => [13, [7, 2, 1, 3]]
  #
  # Returns an Array with two items--an Integer sum of the rolls, and an
  #   Array of the individual roll Integers.
  def self.roll(notation)
    notation = notation.delete(" ").split("d")
    count = notation[0]
    faces = notation[1].split("+")
    dice     = []
    sum      = 0
   
    if faces[1]
      mod = faces[1].to_i
      sum += mod
    else
      mod = 0
    end
    
    (1..count.to_i).each do
      result = rand(1..faces[0].to_i)
      dice << result
      sum += result
    end
    
    return sum, dice, mod
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
  end
end

# A character sheet, basically. Automatically creates lambdas for every action
#   the creature can take, derived from the macros file.
class Creature
  attr_reader :macros
  
  # Initializes a Creature.
  #
  # name - A String that will be set as the creature's name, and displayed as
  #        part of actions rolled.
  # info - An Array of ability scores, actions, and other nessisary data.
  def initialize(name, info)
    @name    = name
    @macros = { }
    
    info["actions"].each do |name, info|
      @macros[name.downcase] = lambda do
        damage = Macros.roll(info[1])
        return "#{@name} uses #{name}\n"\
          "#{Macros.hit(info[0])}\n"\
          "#{damage[0]} #{info[2]} damage | #{damage[1]} + #{damage[2]}"
      end
    end
    
    info.each do |key, value|
      case key
      when "str", "dex", "con", "int", "wis", "cha"
        @macros["roll " + key] = lambda do
          dice_roll = Macros.roll("1d20 + #{(value - 10) / 2}")
          return "#{@name} rolls #{key} for #{dice_roll[0]} "\
            "| #{dice_roll[1]} + #{dice_roll[2]}"
        end
      end
    end
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
      command = gets.rstrip!.downcase

      case command.split[0]
      when "quit"
        exit
      when "roll"
        display(Macros.roll(command.split[1..-1].join))
      when "hit"
        display(Macros.hit(command.split[1].to_i))
      
      else
        creature, remainder = get_phrase(command, @creatures.keys)
        creature = @creatures[creature]
        if creature
          action = get_phrase(remainder, creature.macros.keys)[0]
          action = creature.macros[action]
          if action
            display(action.call)
          end
        end
      end
      
      puts
    end
  end
  
  def display(text)
    file = File.new("log.txt", "a")
    file.write(text + "\n\n")
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
  def get_phrase(command, phrases)
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
end

Main.new.run
