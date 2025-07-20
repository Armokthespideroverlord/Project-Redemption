require "/scripts/util.lua"
require "/interface/games/util.lua"
require "/scripts/vec2.lua"
require "/interface/games/fossilgame/generator.lua"
require "/interface/games/fossilgame/tools.lua"
require "/interface/games/fossilgame/tileset.lua"
require "/interface/games/fossilgame/ui.lua"

-- Backup the old initGame function
local oldInitGame = initGame

function hookedInitGame()
  self.drawActions = {}

  local treasureTypes = config.getParameter("treasureConfig")
  local treasure = treasureTypes[self.treasureType]

  local generator = LevelGenerator:new({SquareTool, CrossTool}, treasure)

  generator.toolRockChance = config.getParameter("toolRockChance", 0.5)
  generator.randomRockChance = config.getParameter("randomRockChance", 0.3)

  local size = {10, 9}
  local position = {30, 39}

  local level, toolUses = generator:generate(size, 16, position, self.tileData[1], self.tileData[2], self.tileData[3], treasure)
  self.level = level

  if config.getParameter("toolType") == "master" then
    self.tools = {
      BrushTool:new(self.level),
      SquareTool:new(self.level, 0),
      TLeft:new(self.level, 0),
      TRight:new(self.level, 0),
      Dot:new(self.level, 0)
    }
  elseif config.getParameter("toolType") == "student" then
    self.tools = {
      BrushTool:new(self.level),
      VRect:new(self.level, 0),
      HRect:new(self.level, 0),
      CrossTool:new(self.level, 0)
    }
  elseif config.getParameter("toolType") == "grandmaster" then
    self.tools = {
      BrushTool:new(self.level),
      SquareTool:new(self.level, 0),
      TLeft:new(self.level, 0),
      TRight:new(self.level, 0),
      Dot:new(self.level, 0)
    }
  else
    self.tools = {
      BrushTool:new(self.level),
      SquareTool:new(self.level, 0),
      CrossTool:new(self.level, 0)
    }
  end

  for _, tool in pairs(self.tools) do
    tool.uses = tool:calculateUses(toolUses)
    if config.getParameter("toolType") == "grandmaster" then
      tool.uses = tool.uses + 5
    end
  end

  initGui(self.tools)
end

-- Replace the old initGame function with the hooked one
initGame = hookedInitGame

-- The rest of your code
function init()
  gameCanvas = widget.bindCanvas("gameCanvas")

  self.toolButtonSet = RadioButtonSet:new()

  world.sendEntityMessage(pane.sourceEntity(), "setInUse", true)

  getFossilParameters()

  initGame()

  self.state = FSM:new()
  self.state:set(playState)
end