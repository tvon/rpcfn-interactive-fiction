#!/usr/bin/env ruby

require 'pp'

class GameObject

  def initialize(id, block)
    @id = id
    parse(block)
  end

  def parse block
    raise NotImplementedError, "Block parsing not implemented"
  end

end

class Room < GameObject
  # Define attrs?
  attr_accessor :exits, :items, :title, :description, :seenit

  def parse(block)

    @seenit = false  # Need to declare?
    
    @exits = {}
    @items = []
    
    /^  Title: (?<title>.*?)\n +Description:\n +(?<description>.*?)\n  Exits:/m.match(block) do |m|
      @title = m[:title].strip
      @description = m[:description].strip.split.join(' ') # probably a better way to clean this...
    end
    
    ['north', 'south', 'east', 'west', 'enter', 'exit'].each do |d|
      / +Exits:\n.* +#{d} to (?<exit>@.*?)$/m.match(block) do |m|
        @exits[d] = m[:exit]
      end
    end

    / +Objects:\n(?<objects>.*)/m.match(block) do |m|
      m[:objects].split.each do |o|
        @items << o.strip
      end
    end

  end

  def to_s
    @title
  end
  
end

class Item < GameObject

  attr_accessor :id, :description, :terms

  def parse(block)

    / +Terms: (?<terms>.*)\n +Description: (?<description>.*)/m.match(block) do |m|
      @terms = m[:terms].split(', ')
      @description = m[:description].strip.split.join(' ')
    end

  end

  def to_s
    @description
  end

end

class Action < GameObject
  def parse(block)

  end

  def succeeds?(context)
    true
  end
end

class Context
  attr_accessor :room, :command, :inventory, :arg, :items, :rooms

  def initialize
    @inventory = []
  end

  def been_here?
    @room.seenit
  end

  def carrying?(item_id)
    @inventory.include? item_id
  end

  def things_here
    @room.items
  end

  def things_here_to_s
    s = ''
    things_here.each do |id|
      s += @items[id].to_s + "\n"
    end
    s
  end

  #################################
  # Commands
  #################################
  
  def look
    m = (@room.description + "\n" + things_here_to_s)
    return [true, m]
  end

  def take
    item_id = @arg

    # Assume failure unless told otherwise...
    result = [false, 'Do what with the what?']

    things_here.each do |obj|
      if @items[obj].terms.map{ |i| i.downcase }.include? item_id
        @inventory << obj
        things_here.delete obj
        result = [true, 'OK']
      end
    end

    result

  end

  def drop
    item = @arg

    result = [false, "You don't have anything like that."]

    @inventory.each do |obj|
      if @items[obj].terms.map{|i| i.downcase}.include? item
        things_here << obj
        @inventory.delete obj
        result = [true, 'OK']
      end
    end

    result

  end

  def inventory 
    if @inventory.empty?
      result = [false, "You're not carrying anything."]
    else
      s = ''
      @inventory.each do |id|
        s += @items[id].terms.first
      end

      result = [true, s]
    end

    result
  end


  def move(direction)
    if @room.exits.has_key? direction
      @room = @rooms[ @room.exits[ direction ] ]
    else
      return [false, "There is no way to go in that direction"]
    end
  end

  def method_missing(sym, *args)
    cmd = sym.to_s
    if cmd
      if ['north', 'south', 'east', 'west', 'enter', 'exit'].include? cmd
        move(cmd)
      end
    end
  end


end

# TODO?  Declare command core name, any aliases and success/failure mesages.
class Command
  attr_accessor :state

  def initialize(name, success, failure)
    @name = name
    @success = success
    @failure = failure
  end
end

# TODO: scan item descriptions for "terms" and distinguish in output to make
# clear what you have to type to refer to that item.
class OutputWriter

  def initialize(output)
    @output = output
  end

  def error(s)
    @output.write "\033[31m#{s}\033[0m\n" 
  end

  def success(s)
    @output.write "\033[34m#{s}\033[0m\n" 
  end

  def write(s)
    @output.write "#{s}\n"
  end

  def puts(s)
    @output.write s
  end

end

class Game

  def initialize(story_path, options={})

    @input  = options.fetch(:input)  { $stdin  }
    @output = options.fetch(:output) { $stdout }

    @writer = OutputWriter.new(@output)

    @aliases = {}

    %w{north south east west enter exit look take drop inventory quit}.each { |c| @aliases[c] = c }

    parse_file story_path

  end

  def parse_file(path)

    @context = Context.new
    rooms = {}

    open(path, 'rb') do |f|
      # Inelegant but effective, initially just scan for each object type we know about
      data = f.read
      data.scan /^Room (.*?):\n(.*?)\n\n/m do |id, block|
        rooms[id] = Room.new(id, block)
        @context.room = rooms[id] unless @context.room # Assumes first shown room is starting point
      end

      @context.rooms = rooms

      items = {}
      data.scan /^Object (?<id>.*?):\n(?<block>.*?)\n\n/m do |id, block|
        items[id] = Item.new(id, block)

        # TODO: Easier to have a mapping for each item term as well as the "internal id"
        items[id].terms.each do |term|
          items[term] = items[id]
        end
      end

      @context.items = items

      /^Synonyms:\n(?<syns>.*)/m.match(data) do |m|
        m[:syns].split("\n").each do |s|
          cmd, syn = s.split(':')
          syn.split(',').each { |a| @aliases[a.strip] = cmd.strip }
        end
      end

    end

  end

  def play!
    start!
    execute_one_command! until ended?
    @writer.error "You have died of dysentery."
  end

  def start!
    refresh
  end

  def refresh

    # Short summary if we've moved into this room and we've been here before.
    if !@context.been_here?
      @writer.write @context.room.description
      show_items
      @context.room.seenit = true
    elsif %w{north south east west enter exit}.include? @context.command
      @writer.write "You're #{@context.room.to_s}."
    end

  end

  def execute_one_command!
    data = @input.gets.downcase.strip.split

    command = @aliases[data[0]]

    if data.length > 1
      @context.arg = data.drop(1).join(' ')
    end

    if command
      @context.command = command
      success, msg = @context.send(command)
      if success
        @writer.write msg
        refresh
      else
        @writer.error msg
      end
      #refresh if @context.send(command)
    else
      unknown_command
    end

    prompt

  end

  def unknown_command
    @writer.error "...and then?"
  end

  def prompt
    @writer.puts "> "
  end

  def ended?
    @context.command == 'quit'
  end

  def show_items
    @context.things_here.each do |id|
      @writer.write @context.items[id].to_s
    end
  end

end

if $PROGRAM_NAME == __FILE__
  story_path = ARGV[0]
  unless story_path
    warn "Usage: #{$PROGRAM_NAME} STORY_FILE"
    exit 1
  end
  game = Game.new(story_path)
  game.play!
end
