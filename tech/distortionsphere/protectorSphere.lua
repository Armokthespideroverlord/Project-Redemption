require "/scripts/vec2.lua"
require "/scripts/rect.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/tech/doubletap.lua"
require "/scripts/util.lua"

function init()
	sb.logInfo("[ProtectorSphere] : Init start!")

	initCommonParameters() --could require distortionsphere.lua, like the other spheres

	self.chargePitchAdjust = config.getParameter("chargePitchAdjust")
	self.chargeEnergy = config.getParameter("chargeEnergy")
	self.releaseEnergy = config.getParameter("releaseEnergy")
	self.chargeTime = config.getParameter("chargeTime")
	self.launchVelocity = config.getParameter("launchVelocity")
	self.chargeEnergyPerSecond = self.chargeEnergy / self.chargeTime[2]

	self.boostMovementParameters = util.mergeTable(copy(self.transformedMovementParameters), config.getParameter("boostMovementParameters"))
	self.boostTime = config.getParameter("boostTime")

	self.chargeTimer = 0
	self.boostTimer = 0

	self.ignorePlatforms = config.getParameter("ignorePlatforms") --only used once locally, so should be local
	self.damageDisableTime = config.getParameter("damageDisableTime")
	self.damageDisableTimer = 0

	self.spinDamageRange = config.getParameter("spinDamageRange")
	self.boostDamageRange = config.getParameter("boostDamageRange")
	self.spinDamage = 0
	self.boostDamage = 0

	self.headingAngle = nil

	self.normalCollisionSet = {"Block", "Dynamic"}
	if self.ignorePlatforms then --parameter only used once; should replaced with config.getParameter
		self.platformCollisionSet = self.normalCollisionSet
	else
		self.platformCollisionSet = {"Block", "Dynamic", "Platform"}
	end

	self.damageListener = damageListener("damageTaken", function(notifications)
		for _, notification in pairs(notifications) do
			if notification.healthLost > 0 and notification.sourceEntityId ~= entity.id() then
				damaged()
				return --wouldn't it end here anyway?
			end
		end
	end)

	self.primaryLast = false
	self.altLast = false
	self.specialLast = false
	self.jumpLast = false

	self.cooldown = 0

	self.chargingBoost = false

	self.jumpChargeTimer = 0
	self.jumpChargeMax = 2
	self.chargeJumpPower = {20, 80}

	self.weaponChargeTimer = 0
	self.weaponChargeMax = 1

	self.effectCooldown = 0
	self.lastJump = false
	self.spinTimer = 0

	self.trailEffectTimer = 0
	self.sideLastR = false
	self.sideLastL = false
	self.sideLastU = false
	self.sideLastD = false
	self.sideLastRTimer = 0
	self.sideLastLTimer = 0
	self.sideLastUTimer = 0
	self.sideLastDTimer = 0

	self.doubleSpaceTimer = 0

	self.projectileCooldowns = {}

	storage.activeProjectiles = storage.activeProjectiles or {}
end

function initCommonParameters()
	self.angularVelocity = 0
	self.angle = 0
	self.transformFadeTimer = 0

	self.energyCost = config.getParameter("energyCost")
	self.ballRadius = config.getParameter("ballRadius")
	self.ballFrames = config.getParameter("ballFrames")
	self.ballSpeed = config.getParameter("ballSpeed")
	self.transformFadeTime = config.getParameter("transformFadeTime", 0.3)
	self.transformedMovementParameters = config.getParameter("transformedMovementParameters")
	self.transformedMovementParameters.runSpeed = self.ballSpeed
	self.transformedMovementParameters.walkSpeed = self.ballSpeed
	self.basePoly = mcontroller.baseParameters().standingPoly
	self.collisionSet = {"Null", "Block", "Dynamic", "Slippery"}

	self.forceDeactivateTime = config.getParameter("forceDeactivateTime", 3.0)
	self.forceShakeMagnitude = config.getParameter("forceShakeMagnitude", 0.125) 
end

function uninit()
	sb.logInfo("[ProtectorSphere] : Uninit start!")

	animator.setParticleEmitterActive("chargeLeft", false)
	animator.setParticleEmitterActive("chargeRight", false)
	animator.stopAllSounds("chargeLoop")
	storePosition()
	deactivate()

	for i, projectile in pairs(storage.activeProjectiles) do
		world.callScriptedEntity(projectile, "setTarget", nil)
	end
	sb.logInfo("[ProtectorSphere] : Uninit done!")
end

function update(args)
	restoreStoredPosition()

	self.cooldown = math.max(0, self.cooldown - args.dt)
	self.spinTimer = math.max(0, self.spinTimer - args.dt)
	self.sideLastRTimer = math.max(0, self.sideLastRTimer - args.dt)
	self.sideLastLTimer = math.max(0, self.sideLastLTimer - args.dt)
	self.sideLastUTimer = math.max(0, self.sideLastUTimer - args.dt)
	self.sideLastDTimer = math.max(0, self.sideLastDTimer - args.dt)
	self.doubleSpaceTimer = math.max(0, self.doubleSpaceTimer - args.dt)
	self.damageDisableTimer = math.max(0, self.damageDisableTimer - args.dt)
	self.boostTimer = math.max(0, self.boostTimer - args.dt)

	for key, val in pairs(self.projectileCooldowns) do
		self.projectileCooldowns[key] = math.max(0, val - args.dt)
	end

	self.damageListener:update()
	
	local jumpActivated = args.moves["jump"] and not self.lastJump
	self.lastJump = args.moves["jump"]

	if not args.moves["special1"] then
		self.forceTimer = nil
	end

	if self.active then
		status.setResourcePercentage("energyRegenBlock", 1.0)
		updateDirectives()

		if (self.boostTimer > 0) or (self.chargeTimer >= self.chargeTime[1]) or (math.abs(self.angularVelocity) > 40) then
			status.addEphemeralEffect("invulnerable", 0.1)
			if self.chargeTimer >= self.chargeTime[1] then
				self.spinDamage = self.spinDamageRange[1] + ((self.spinDamageRange[2] - self.spinDamageRange[1]) * chargeRatio())
				dropProjectile("spinProjectile", self.spinDamage, true)
				animator.setParticleEmitterActive("spinning", true)

			elseif self.boostTimer > 0 then
				self.boostDamage = self.boostDamageRange[1] + ((self.boostDamageRange[2] - self.boostDamageRange[1]) * (math.abs(self.angularVelocity) / 100))
				dropProjectile("boostProjectile", self.boostDamage, true)
				animator.setParticleEmitterActive("boosting", true)
			else
				dropProjectile("speedingProjectile", self.spinDamageRange[1], true)
				animator.setParticleEmitterActive("boosting", true)
			end
		else
			animator.setParticleEmitterActive("boosting", false)
			animator.setParticleEmitterActive("spinning", false)
		end

		local groundDirection
		if self.damageDisableTimer == 0 then
			groundDirection = findGroundDirection()
		end

		if not self.specialLast and args.moves["special1"] then
			sb.logInfo("[ProtectorSphere] : Morphing to normal!")
			attemptActivation()
			if not self.forceTimer then
				self.chargeDirection = mcontroller.facingDirection()
				self.chargeTimer = 0
			end
			animator.setGlobalTag("ballDirectives", "")
		end

		if self.boostTimer > 0 then
			animator.setGlobalTag("ballDirectives", "?border=1;73daff80;73daff00")
			mcontroller.controlParameters(self.boostMovementParameters)
		else
			animator.setGlobalTag("ballDirectives", "")
			mcontroller.controlParameters(self.transformedMovementParameters)
		end

		if self.chargingBoost and status.overConsumeResource("energy", self.chargeEnergyPerSecond * args.dt) then
			status.setResourcePercentage("energyRegenBlock", 1.0)
			self.chargeTimer = math.min(self.chargeTimer + args.dt, self.chargeTime[2])
			self.angularVelocity = -mcontroller.facingDirection() * self.launchVelocity * chargeRatio()
			mcontroller.controlModifiers({movementSuppressed = true, facingSuppressed = true})
			mcontroller.controlApproachXVelocity(0, 1000)
			startChargeEffects()
			animator.setSoundPitch("chargeLoop", 1.0 + chargeRatio(), 0)
			mcontroller.setVelocity({0, 0})

			if self.chargeTimer >= self.chargeTime[1] then
				animator.setGlobalTag("ballDirectives", "?border=1;73daff80;73daff00")
				if self.chargeTimer == self.chargeTime[2] then
					animator.setGlobalTag("ballDirectives", "?border=2;c0fbff80;27abff00")
				end
			else
				animator.setGlobalTag("ballDirectives", "")
			end

		else
			--animator.setGlobalTag("ballDirectives", "")
			self.chargeTimer = 0
			self.chargingBoost = false
			animator.setSoundPitch("chargeLoop", 1.0, 0)
			stopChargeEffects()

			if groundDirection then
				if not self.headingAngle then
					self.headingAngle = (math.atan(groundDirection[2], groundDirection[1]) + math.pi / 2) % (math.pi * 2)
				end

				local moveX = 0
				if args.moves["right"] then moveX = moveX + 1 end
				if args.moves["left"] then moveX = moveX - 1 end
				if moveX ~= 0 then
					-- find any collisions in the moving direction, and adjust heading angle *up* until there is no collision
					-- this makes the heading direction follow concave corners
					local adjustment = 0
					for a = 0, math.pi, math.pi / 4 do
						local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.25, 0}, self.headingAngle + (moveX * a)))
						adjustment = moveX * a
						if not world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
							break
						end
					end
					self.headingAngle = self.headingAngle + adjustment

					-- find empty space in the moving direction and adjust heading angle *down* until it collides
					-- adjust to the angle *before* the collision occurs
					-- this makes the heading direction follow convex corners
					adjustment = 0
					for a = 0, -math.pi, -math.pi / 4 do
						local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.25, 0}, self.headingAngle + (moveX * a)))
						if world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
							break
						end
						adjustment = moveX * a
					end
					self.headingAngle = self.headingAngle + adjustment

					-- apply a gravitation like force in the ground direction, while moving in the controlled direction
					-- Note: this ground force causes weird collision when moving up slopes, result is you move faster up slopes
					local groundAngle = self.headingAngle - (math.pi / 2)
					mcontroller.controlApproachVelocity(vec2.withAngle(groundAngle, self.ballSpeed), 300)

					local moveDirection = vec2.rotate({moveX, 0}, self.headingAngle)
					mcontroller.controlApproachVelocityAlongAngle(math.atan(moveDirection[2], moveDirection[1]), self.ballSpeed, 2000)

					self.angularVelocity = -moveX * self.ballSpeed

				else
					mcontroller.controlApproachVelocity({0, 0}, 2000)
					self.angularVelocity = 0
				end

				if args.moves["jump"] then
					local gDir = findGroundDirection()
					mcontroller.setVelocity(vec2.mul(gDir, -50))
				else
					-- Nothing
				end

				mcontroller.controlDown()
				updateAngularVelocity(args.dt)

				self.transformedMovementParameters.gravityEnabled = false
			else
				updateAngularVelocity(args.dt)
				self.transformedMovementParameters.gravityEnabled = true
			end
		end

		if args.moves["primaryFire"] and not self.primaryLast then -- Hold
			self.chargingBoost = true
			self.transformedMovementParameters.gravityEnabled = false
			mcontroller.setVelocity({0, 0})

		elseif not args.moves["primaryFire"] and self.primaryLast and self.chargingBoost then -- Release
			local aimVec = {0, 0.1}
			local neutral = true
			if args.moves["right"] then
				aimVec[1] = 1
				neutral = false
			elseif args.moves["left"] then
				aimVec[1] = -1
				neutral = false
			end
			if args.moves["up"] then
				aimVec[2] = 1
				neutral = false
			elseif args.moves["down"] then
				aimVec[2] = -1
				neutral = false
			end

			if neutral then
				aimVec = vec2.norm(vec2.sub(tech.aimPosition(), mcontroller.position()))
				aimVec = vec2.add(aimVec, {0, 0.1})
			end

			if self.chargeTimer >= self.chargeTime[1] then
				local launchVelocity = vec2.mul({self.launchVelocity * aimVec[1], self.launchVelocity * aimVec[2]}, chargeRatio())
				mcontroller.setVelocity(launchVelocity)
				animator.playSound("launch")
				self.boostTimer = self.boostTime
				status.overConsumeResource("energy", self.releaseEnergy)
			else
				self.angularVelocity = 0
			end
			stopChargeEffects()
			animator.setSoundPitch("chargeLoop", 1.0, 0)

			self.chargeTimer = 0
			self.chargingBoost = false
			self.transformedMovementParameters.gravityEnabled = true
		else

		end

		updateRotationFrame(args.dt)

	else
		self.chargeTimer = 0
		animator.setSoundPitch("chargeLoop", 1.0, 0)
		animator.setParticleEmitterActive("boosting", false)
		animator.setParticleEmitterActive("spinning", false)
		stopChargeEffects()
		self.chargingBoost = false
		self.angularVelocity = 0
		self.boostTimer = 0

		self.headingAngle = nil
		if not self.specialLast and args.moves["special1"] then
			sb.logInfo("[ProtectorSphere] : Morphing to sphere!")
			attemptActivation()
			compileDirectives()
			updateDirectives()
		end
	end

	


	updateTransformFade(args.dt)
	self.lastPosition = mcontroller.position()

	-- "left", "right", "down", "up", "jump", "primaryFire", "altFire", "special", "special1", "special2", "special3"
	self.specialLast = args.moves["special1"] or args.moves["special2"] or args.moves["special3"]
	self.primaryLast = args.moves["primaryFire"]
	self.altLast = args.moves["altFire"]
	self.jumpLast = args.moves["jump"]
	self.sideLastR = args.moves["right"]
	self.sideLastL = args.moves["left"]
	self.sideLastU = args.moves["up"]
	self.sideLastD = args.moves["down"]

	--mcontroller.setVelocity(vec2.mul(vec2.norm(vec2.sub(tech.aimPosition(), mcontroller.position())), 10))
	local val1 = vec2.mul(vec2.norm(vec2.sub(tech.aimPosition(), mcontroller.position())), 2)
	local pos1 = mcontroller.position()
	local pos2 = vec2.add(mcontroller.position(), val1)
	world.debugLine(pos1, pos2, "#FFFF00")
	world.debugText("Aim: [" .. val1[1] .. ", " .. val1[2] .. "]" , vec2.add(mcontroller.position(), {0, 3}), "#DDBB80")
	world.debugText("AV: " .. self.angularVelocity , vec2.add(mcontroller.position(), {0, 3.5}), "#EEBB70")

	local vi = 0
	for key, val in pairs(self.projectileCooldowns) do
		world.debugText(key .. ": " .. val , vec2.add(mcontroller.position(), {0, 4.0 + (vi * 0.5)}), "#DD9950")
		vi = vi + 1
	end
	
	updateProjectiles()
end

function compileDirectives()
	
end

function updateDirectives()
	animator.setGlobalTag("ballDirectives", "")
end


-- Default stuff
function attemptActivation()
	if not self.active and not tech.parentLounging()
		and not status.statPositive("activeMovementAbilities") and status.overConsumeResource("energy", self.energyCost) then

		local pos = transformPosition()
		if pos then
			mcontroller.setPosition(vec2.add(pos, {0, 1}))
			mcontroller.setYVelocity(mcontroller.yVelocity() + 5)
			activate()
		end

	elseif self.active then
		local pos = restorePosition()
		if pos then
			mcontroller.setPosition(pos)
			mcontroller.setYVelocity(mcontroller.yVelocity() + 5)
			deactivate()
		elseif not self.forceTimer then
			animator.playSound("forceDeactivate", -1)
			self.forceTimer = 0
		end
	end
end

function checkForceDeactivate(dt)
	animator.resetTransformationGroup("ball")

	if self.forceTimer then
		self.forceTimer = self.forceTimer + dt
		mcontroller.controlModifiers({
			movementSuppressed = true
		})

		local shake = vec2.mul(vec2.withAngle((math.random() * math.pi * 2), self.forceShakeMagnitude), self.forceTimer / self.forceDeactivateTime)
		animator.translateTransformationGroup("ball", shake)
		if self.forceTimer >= self.forceDeactivateTime then
			deactivate()
			self.forceTimer = nil
		else
			attemptActivation()
		end
		return true
	else
		animator.stopAllSounds("forceDeactivate")
		return false
	end
end

function storePosition()
	if self.active then
		storage.restorePosition = restorePosition()

		-- try to restore position. if techs are being switched, this will work and the storage will
		-- be cleared anyway. if the client's disconnecting, this won't work but the storage will remain to
		-- restore the position later in update()
		if storage.restorePosition then
			storage.lastActivePosition = mcontroller.position()
			mcontroller.setPosition(storage.restorePosition)
		end
	end
end

function restoreStoredPosition()
	if storage.restorePosition then
		-- restore position if the player was logged out (in the same planet/universe) with the tech active
		if vec2.mag(vec2.sub(mcontroller.position(), storage.lastActivePosition)) < 1 then
			mcontroller.setPosition(storage.restorePosition)
		end
		storage.lastActivePosition = nil
		storage.restorePosition = nil
	end
end

function updateAngularVelocity(dt)
	if mcontroller.groundMovement() or self.spinTimer > 0 then
		-- If we are on the ground, assume we are rolling without slipping to
		-- determine the angular velocity
		local positionDiff = world.distance(self.lastPosition or mcontroller.position(), mcontroller.position())
		self.angularVelocity = -vec2.mag(positionDiff) / dt / self.ballRadius

		if positionDiff[1] > 0 then
			self.angularVelocity = -self.angularVelocity
		end
	end
end

function updateRotationFrame(dt)
	self.angle = math.fmod(math.pi * 2 + self.angle + self.angularVelocity * dt, math.pi * 2)

	-- Rotation frames for the ball are given as one *half* rotation so two
	-- full cycles of each of the ball frames completes a total rotation.
	local rotationFrame = math.floor(self.angle / math.pi * self.ballFrames) % self.ballFrames
	animator.setGlobalTag("rotationFrame", rotationFrame)
end

function updateTransformFade(dt)
	if self.transformFadeTimer > 0 then
		self.transformFadeTimer = math.max(0, self.transformFadeTimer - dt)
		--animator.setGlobalTag("ballDirectives", string.format("?fade=FFFFFFFF;%.1f", math.min(1.0, self.transformFadeTimer / (self.transformFadeTime - 0.15))))

	elseif self.transformFadeTimer < 0 then
		self.transformFadeTimer = math.min(0, self.transformFadeTimer + dt)
		if not self.camo then
			tech.setParentDirectives(string.format("?fade=ffff;%.1f", math.min(1.0, -self.transformFadeTimer / (self.transformFadeTime - 0.15))))
		else
			tech.setParentDirectives(self.camoDirectives)
		end
	else
		--animator.setGlobalTag("ballDirectives", "")
		if not self.camo then
			tech.setParentDirectives()
		else
			tech.setParentDirectives(self.camoDirectives)
		end
	end
end

function positionOffset()
	return minY(self.transformedMovementParameters.collisionPoly) - minY(self.basePoly)
end

function transformPosition(pos)
	pos = pos or mcontroller.position()
	local groundPos = world.resolvePolyCollision(self.transformedMovementParameters.collisionPoly, {pos[1], pos[2] - positionOffset()}, 1, self.collisionSet)
	if groundPos then
		return groundPos
	else
		return world.resolvePolyCollision(self.transformedMovementParameters.collisionPoly, pos, 1, self.collisionSet)
	end
end

function restorePosition(pos)
	pos = pos or mcontroller.position()
	local groundPos = world.resolvePolyCollision(self.basePoly, {pos[1], pos[2] + positionOffset()}, 1, self.collisionSet)
	if groundPos then
		return groundPos
	else
		return world.resolvePolyCollision(self.basePoly, pos, 1, self.collisionSet)
	end
end

function activate()
	if not self.active then
		animator.burstParticleEmitter("activateParticles")
		animator.playSound("activate")
		animator.setAnimationState("ballState", "activate")
		self.angularVelocity = 0
		self.angle = 0
		self.transformFadeTimer = self.transformFadeTime
	end
	tech.setParentHidden(true)
	tech.setParentOffset({0, positionOffset()})
	tech.setToolUsageSuppressed(true)
	status.setPersistentEffects("movementAbility", {{stat = "activeMovementAbilities", amount = 1}})
	self.active = true
end

function deactivate()
	if self.active then
		animator.burstParticleEmitter("deactivateParticles")
		animator.playSound("deactivate")
		animator.setAnimationState("ballState", "deactivate")
		self.transformFadeTimer = -self.transformFadeTime
	else
		animator.setAnimationState("ballState", "off")
	end
	animator.stopAllSounds("forceDeactivate")
	--animator.setGlobalTag("ballDirectives", "")
	tech.setParentHidden(false)
	tech.setParentOffset({0, 0})
	tech.setToolUsageSuppressed(false)
	status.clearPersistentEffects("movementAbility")
	self.angle = 0
	self.active = false
end

function minY(poly)
	local lowest = 0
	for _,point in pairs(poly) do
		if point[2] < lowest then
			lowest = point[2]
		end
	end
	return lowest
end

function damaged()
	if self.active then
		self.damageDisableTimer = self.damageDisableTime
	end
end

function findGroundDirection()
	for i = 0, 3 do
		local angle = (i * math.pi / 2) - math.pi / 2
		local collisionSet = i == 1 and self.platformCollisionSet or self.normalCollisionSet
		local testPos = vec2.add(mcontroller.position(), vec2.withAngle(angle, 0.25))
		if world.polyCollision(poly.translate(mcontroller.collisionPoly(), testPos), nil, collisionSet) then
			return vec2.withAngle(angle, 1.0)
		end
	end
end

function chargeRatio()
	return self.chargeTimer / self.chargeTime[2]
end

function startChargeEffects()
	if not self.chargeSoundPlaying then
		animator.playSound("chargeLoop", -1)
		self.chargeSoundPlaying = true
	end
	if self.chargeTimer >= self.chargeTime[1] then
		animator.setParticleEmitterActive("chargeLeft", true)
		animator.setParticleEmitterActive("chargeRight", true)
	end
end

function stopChargeEffects()
	if self.chargeSoundPlaying then
		animator.stopAllSounds("chargeLoop")
		self.chargeSoundPlaying = false
	end
	animator.setParticleEmitterActive("chargeLeft", false)
	animator.setParticleEmitterActive("chargeRight", false)
end



-- New stuff
function dropProjectile(tbl, setDamage, alterTTL)
	local ProjectileData = config.getParameter(tbl)
	ProjectileData.projectileParameters.powerMultiplier = 1.0
	ProjectileData.projectileParameters.power = setDamage or ProjectileData.projectileParameters.power
	
	--ProjectileData.projectileParameters.movementSettings.gravityMultiplier = 0.0
	--ProjectileData.projectileParameters.movementSettings.collisionEnabled = false

	if ProjectileData.cooldowns then
		local isCooled = true

		for key, val in pairs(ProjectileData.cooldowns) do
			if self.projectileCooldowns[key] then
				if self.projectileCooldowns[key] > 0 then
					isCooled = false
				end
			else
				self.projectileCooldowns[key] = val
			end
			if alterTTL then
				if ProjectileData.projectileParameters.timeToLive < val then
					ProjectileData.projectileParameters.timeToLive = val
				end
			end
		end

		if isCooled then
			local projectileId = spawnThatProjectile(ProjectileData)
			for key, val in pairs(ProjectileData.cooldowns) do
				self.projectileCooldowns[key] = val
			end
		end
		
	else
		local projectileId = spawnThatProjectile(ProjectileData)
	end

	if projectileId then
		storage.activeProjectiles[#storage.activeProjectiles + 1] = projectileId
	end
end

function spawnThatProjectile(projData)
	return world.spawnProjectile(
		projData.projectileType, 
		vec2.add(mcontroller.position(), projData.offset or {0, 0}), 
		entity.id(), 
		projData.aim or {0, 0}, 
		projData.follow or false, 
		projData.projectileParameters
	)
end

function updateProjectiles()
	local newProjectiles = {}
	for i, projectile in pairs(storage.activeProjectiles) do
		if world.entityExists(projectile) then
			newProjectiles[#newProjectiles + 1] = projectile
		end
	end
	storage.activeProjectiles = newProjectiles
end

function triggerProjectiles()
	if #storage.activeProjectiles > 0 then
		
	end
	for i, projectile in pairs(storage.activeProjectiles) do
		world.callScriptedEntity(projectile, "trigger")
	end
end


-- Maths
function angDiff(to, from)
	local a = to - from
	if (a > 1) then
		a = a - 2
	elseif (a < -1) then
		a = a + 2
	end
	return a
end

function clamp(val, minval, maxval)
	return math.max(minval, math.min(val, maxval))
end

function inverseClamp(val, minval, maxval, setto)
	if val < maxval and val > minval then
		return setto
	end
	return val
end

function directionTwoVec(vector1, vector2)
	local angle = math.atan(vector2[2] - vector1[2], vector2[1] - vector1[1])
	return angle --?? return math.atan(vector2[2] - vector1[2], vector2[1] - vector1[1])
end