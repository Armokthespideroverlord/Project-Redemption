require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/vehicles/r-dropship/r-dropship.lua"

function init()
  initShip()

  self.lastAltFire = false
end

function update(dt)
  local moveDir = {0, 0}
  if vehicle.controlHeld("seat", "right") then
    moveDir[1] = moveDir[1] + 1
  end
  if vehicle.controlHeld("seat", "left") then
    moveDir[1] = moveDir[1] - 1
  end
  if vehicle.controlHeld("seat", "up") then
    moveDir[2] = moveDir[2] + 1
  end
  if vehicle.controlHeld("seat", "down") then
    moveDir[2] = moveDir[2] - 1
  end

  if vehicle.controlHeld("seat", "primaryFire") then
    startFiring()
  else
    stopFiring()
  end

  local altFire = vehicle.controlHeld("seat", "altFire")
  if altFire and not self.lastAltFire then
    toggleBlinds()
  end
  self.lastAltFire = altFire
  
  local driver = vehicle.entityLoungingIn("seat")
  updateShip(dt, driver, moveDir)
end
