require "/scripts/vec2.lua"
require "/scripts/poly.lua"

function init()
  self.chargeTime = config.getParameter("chargeTime")
  self.boostTime = config.getParameter("boostTime")
  self.boostSpeed = config.getParameter("boostSpeed")
  self.boostForce = config.getParameter("boostForce")
  self.rocketJumpCount = math.max(1, config.getParameter("rocketJumpCount", 3))

  self.wallSlideParameters = config.getParameter("wallSlideParameters", {
    airJumpProfile = {jumpInitialPercentage = 1.0},
    airForce = 0,
    airFriction = 10.0
  })
  self.wallJumpXVelocity = config.getParameter("wallJumpXVelocity", 15)
  self.wallGrabFreezeTime = config.getParameter("wallGrabFreezeTime", 0.15)
  self.wallGrabFreezeTimer = 0
  self.wallReleaseTime = config.getParameter("wallReleaseTime", 0.15)
  self.wallReleaseTimer = 0
  self.wallDetectThreshold = config.getParameter("wallDetectThreshold", 1)
  self.wallCollisionSet = config.getParameter("wallCollisionSet", {"Dynamic", "Block"})

  buildSensors()
  self.availableJumps = self.rocketJumpCount
  self.wall = nil

  idle()
end

function uninit()
  idle()
  releaseWall()
end

function update(args)
  local jumpActivated = args.moves["jump"] and not self.lastJump
  self.lastJump = args.moves["jump"]

  self.stateTimer = math.max(0, self.stateTimer - args.dt)

  local lrInput
  if args.moves["left"] and not args.moves["right"] then
    lrInput = "left"
  elseif args.moves["right"] and not args.moves["left"] then
    lrInput = "right"
  end

  if mcontroller.groundMovement() or mcontroller.liquidMovement() then
    if self.state ~= "idle" then
      idle()
    end
    self.availableJumps = self.rocketJumpCount
    if self.wall then
      releaseWall()
    end
  end

  if self.state == "idle" then
    if self.wall then
      mcontroller.controlParameters(self.wallSlideParameters)

      if not checkWall(self.wall) or status.statPositive("activeMovementAbilities") then
        releaseWall()
      elseif jumpActivated then
        doWallJump()
        return
      else
        if lrInput and lrInput ~= self.wall then
          self.wallReleaseTimer = self.wallReleaseTimer + args.dt
        else
          self.wallReleaseTimer = 0
        end

        if self.wallReleaseTimer > self.wallReleaseTime then
          releaseWall()
        else
          mcontroller.controlFace(self.wall == "left" and 1 or -1)
          if self.wallGrabFreezeTimer > 0 then
            self.wallGrabFreezeTimer = math.max(0, self.wallGrabFreezeTimer - args.dt)
            mcontroller.controlApproachVelocity({0, 0}, 1000)
            if self.wallGrabFreezeTimer == 0 then
              animator.setParticleEmitterActive("wallSlide.right", true)
              animator.playSound("wallSlideLoop", -1)
            end
          end
        end
      end
    elseif not mcontroller.groundMovement() and not mcontroller.liquidMovement() and lrInput and not mcontroller.jumping() and checkWall(lrInput) and not status.statPositive("activeMovementAbilities") then
      grabWall(lrInput)
      return
    elseif jumpActivated and canRocketJump() then
      charge()
    end
  elseif self.state == "charge" then
    if self.stateTimer > 0 then
      mcontroller.controlApproachVelocity({0, 0}, self.boostForce)
      mcontroller.controlModifiers({movementSuppressed = true})
    else
      local direction = {0, 0}
      if args.moves["right"] then direction[1] = direction[1] + 1 end
      if args.moves["left"] then direction[1] = direction[1] - 1 end
      if args.moves["up"] then direction[2] = direction[2] + 1 end
      if args.moves["down"] then direction[2] = direction[2] - 1 end

      if vec2.eq(direction, {0, 0}) then direction = {0, 1} end

      boost(direction)
    end
  elseif self.state == "boost" then
    if self.stateTimer > 0 then
      mcontroller.controlApproachVelocity(self.boostVelocity, self.boostForce)
    else
      idle()
    end
  end

  if self.wall then
    animator.setFlipped(self.wall == "left")
  else
    animator.setFlipped(mcontroller.facingDirection() < 0)
  end
end

function canRocketJump()
  return self.availableJumps > 0
      and not mcontroller.jumping()
      and not mcontroller.canJump()
      and not mcontroller.liquidMovement()
      and not status.statPositive("activeMovementAbilities")
end

function charge()
  self.state = "charge"
  self.stateTimer = self.chargeTime
  status.setPersistentEffects("movementAbility", {{stat = "activeMovementAbilities", amount = 1}})
  tech.setParentState("fly")
  animator.setParticleEmitterActive("rocketParticles", true)
  animator.playSound("charge")
  animator.playSound("chargeLoop", -1)
end

function boost(direction)
  self.state = "boost"
  self.stateTimer = self.boostTime
  self.availableJumps = math.max(0, self.availableJumps - 1)
  self.boostVelocity = vec2.mul(vec2.norm(direction), self.boostSpeed)
  tech.setParentState()
  animator.stopAllSounds("charge")
  animator.stopAllSounds("chargeLoop")
  animator.playSound("boost")
end

function idle()
  self.state = "idle"
  self.stateTimer = 0
  status.clearPersistentEffects("movementAbility")
  tech.setParentState()
  animator.setParticleEmitterActive("rocketParticles", false)
  animator.stopAllSounds("charge")
  animator.stopAllSounds("chargeLoop")
end

function buildSensors()
  local bounds = poly.boundBox(mcontroller.baseParameters().standingPoly)
  self.wallSensors = {right = {}, left = {}}
  for _, offset in pairs(config.getParameter("wallSensors", {1.0, 1.75, 2.5})) do
    table.insert(self.wallSensors.left, {bounds[1] - 0.1, bounds[2] + offset})
    table.insert(self.wallSensors.right, {bounds[3] + 0.1, bounds[2] + offset})
  end
end

function checkWall(wall)
  local pos = mcontroller.position()
  local hits = 0
  for _, offset in pairs(self.wallSensors[wall]) do
    if world.pointCollision(vec2.add(pos, offset), self.wallCollisionSet) then
      hits = hits + 1
    end
  end
  return hits >= self.wallDetectThreshold
end

function grabWall(wall)
  self.wall = wall
  self.wallGrabFreezeTimer = self.wallGrabFreezeTime
  self.wallReleaseTimer = 0
  mcontroller.setVelocity({0, 0})
  tech.setToolUsageSuppressed(true)
  tech.setParentState("fly")
  animator.playSound("wallGrab")
end

function releaseWall()
  if not self.wall then return end
  self.wall = nil
  tech.setToolUsageSuppressed(false)
  tech.setParentState()
  animator.setParticleEmitterActive("wallSlide.left", false)
  animator.setParticleEmitterActive("wallSlide.right", false)
  animator.stopAllSounds("wallSlideLoop")
end

function doWallJump()
  animator.setFlipped(self.wall == "left")
  mcontroller.controlJump(true)
  animator.playSound("wallJumpSound")
  animator.burstParticleEmitter("wallJump.right")
  mcontroller.setXVelocity(self.wall == "left" and self.wallJumpXVelocity or -self.wallJumpXVelocity)
  releaseWall()
end
