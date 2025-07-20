require "/scripts/vec2.lua"
function init()
local b = mcontroller.boundBox()
  animator.setParticleEmitterOffsetRegion("jetpackParticles", {b[1], b[2] + 0.2, b[3], b[2] + 0.3})
  self.jetpackSpeed = config.getParameter("jetpackSpeed")
  self.jetpackControlForce = config.getParameter("jetpackControlForce")
  self.energyUsagePerSecond = config.getParameter("energyUsagePerSecond")
self.holdingJump = false
self.active = false
  self.lastYVel = mcontroller.yVelocity()
end

function input(args)
  if args.moves["jump"] and mcontroller.jumping() then
    self.holdingJump = true
  elseif not args.moves["jump"] then
    self.holdingJump = false
  end

  if args.moves["jump"] and not status.statPositive("activeMovementAbilities") and not mcontroller.canJump() and not self.holdingJump then
    return "jetpack"
  else
    return nil
  end
end

function update(args)


	if args.moves["jump"] and mcontroller.jumping() then
		self.holdingJump = true
	elseif not args.moves["jump"] then
		self.holdingJump = false
	end
  local action = input(args)
local jetpack = args.moves["jump"] and (args.moves["down"] and mcontroller.yVelocity() <= -40 or not args.moves["down"]) and not mcontroller.canJump() and not self.holdingJump
  if jetpack and status.consumeResource("energy", self.energyUsagePerSecond * args.dt) then
    animator.setAnimationState("jetpack", "on")
    mcontroller.controlApproachYVelocity(self.jetpackSpeed, self.jetpackControlForce)

    if not self.active then
      animator.playSound("activate")
    end
    self.active = true
    animator.setParticleEmitterActive("jetpackParticles", true)
  else
    self.active = false
    animator.setAnimationState("jetpack", "off")
    animator.setParticleEmitterActive("jetpackParticles", false)
  end
  self.lastYVel = mcontroller.yVelocity()
end