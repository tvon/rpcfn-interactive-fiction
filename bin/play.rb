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
    
    @exits = {} # XXX
    @items = []
    
    # Could do this all in one big fugly regex, but this is cleaner and clearer
    /^  Title: (?<title>.*?)\n +Description:\n +(?<description>.*?)\n  Exits:/m.match(block) do |m|
      @title = m[:title].strip
      @description = m[:description].strip.split.join(' ') # probably a better way to clean this...
    end
    
    ['north', 'south', 'east', 'west', 'enter', 'exit'].each do |d|
      / +Exits:\n.* +#{d} to (?<exit>@.*?)$/m.match(block) do |m|
        @exits[d] = m[:exit]
      end
    end

    # Of course this means object must come last
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

class Obj < GameObject

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
  attr_accessor :room, :command, :inventory, :arg, :items

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

  #################################
  # Commands
  #################################

  def take
    item_id = @context.arg

    start_len = @context.inventory.length

    @context.things_here.each do |obj|
      if @items[obj].terms.map{|i| i.downcase}.include? item_id
        @context.inventory << obj
        @context.things_here.delete obj
        @output.write "OK\n"
      end
    end

    if start_len == @context.inventory.length
      @output.write "Do what with the what?\n"
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

# TODO: colorized output via "writer.error 'foo'", "writer.success 'OK'", 'writer.embiggen "something"'
# Related: scan item descriptions for "terms" and distinguish in output to make
# clear what you have to type to refer to that item.
class OutputWriter

  def initialize(output)
    @output = output
  end

  def error(s)
    @output.write "\033[31m#{s}\033[0m\n" 
  end

  def success(s)
    @output.write "\033[32m#{s}\033[0m\n" 
  end

end

class Game

  def initialize(story_path, options={})

    @input  = options.fetch(:input)  { $stdin  }
    @output = options.fetch(:output) { $stdout }

    #@writer = OutputWriter.new(@output)

    @aliases = {}

    %w{north south east west enter exit look take drop inventory quit}.each { |c| @aliases[c] = c }

    parse_file story_path

  end

  def parse_file(path)

    @rooms = {}
    @context = Context.new

    open(path, 'rb') do |f|
      # Inelegant but effective, initially just scan for each object type we know about
      data = f.read
      data.scan /^Room (.*?):\n(.*?)\n\n/m do |id, block|
        @rooms[id] = Room.new(id, block)
        @context.room = @rooms[id] unless @context.room # Assumes first shown room is starting point
      end

      items = {}
      data.scan /^Object (?<id>.*?):\n(?<block>.*?)\n\n/m do |id, block|
        items[id] = Obj.new(id, block)

        # TODO: Easier to have a mapping for each item term as well as the "internal id"
        #items[id].terms.each do |term|
        #  items[term] = items[id]
        #end

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
  end

  def start!
#    @output.write @context.room.description + "\n"
#    @context.room.seenit = true
#    show_items
    refresh
  end

  def refresh

    # Short summary if we've moved into this room and we've been here before.
    if !@context.been_here?
      @output.write @context.room.description + "\n"
      show_items
      @context.room.seenit = true
    elsif %w{north south east west enter exit}.include? @context.command
      @output.write "You're " + @context.room.to_s + ".\n"
    end

    prompt

  end

  def execute_one_command!
    data = @input.gets.downcase.strip.split

    command = @aliases[data[0]]

    if data.length > 1
      @context.arg = data.drop(1).join(' ')
    end

    if command
      @context.command = command
      refresh if send(command)
    else
      unknown_command
    end
  end

  def unknown_command
    @output.write "and then?\n"
    prompt
  end

  def prompt
    @output.write "> "
  end

  def ended?
    @context.command == 'quit'
  end

  def method_missing(sym, *args)
    cmd = @aliases[sym.to_s]
    if cmd
      if ['north', 'south', 'east', 'west', 'enter', 'exit'].include? cmd
        handle_movement
      end
    end
  end

  def show_items
    @context.things_here.each do |id|
      @output.write @context.items[id].to_s + "\n"
    end
  end

  #################################
  # Commands
  #################################

  def drop
    item = @context.arg
    start_len = @context.inventory.length
    @context.inventory.each do |obj|
      if @context.items[obj].terms.map{|i| i.downcase}.include? item
        @context.things_here << obj
        @context.inventory.delete obj
        @output.write "OK\n"
      end
    end

    if start_len == @context.inventory.length
      @output.write "You don't have anything like that\n"
    end

  end

  def look
    @output.write @context.room.description + "\n"
    show_items
  end

  def handle_movement
    if @context.room.exits.has_key? @context.command
      @context.room = @rooms[ @context.room.exits[ @context.command ] ]
    else
      @output.write "There is no way to go in that direction\n"
      prompt
      false
    end
  end

  def inventory 
    if @context.inventory.empty?
      @output.write "You're not carrying anything\n"
    else
      @context.inventory.each do |id|
        @output.write @context.items[id].terms.first + "\n"
      end
    end
  end

  def take
    item_id = @context.arg

    start_len = @context.inventory.length

    @context.things_here.each do |obj|
      if @context.items[obj].terms.map{|i| i.downcase}.include? item_id
        @context.inventory << obj
        @context.things_here.delete obj
        @output.write "OK\n"
      end
    end

    if start_len == @context.inventory.length
      @output.write "Do what with the what?\n"
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
