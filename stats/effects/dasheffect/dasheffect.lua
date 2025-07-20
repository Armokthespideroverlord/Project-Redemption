function init()
  local bounds = mcontroller.boundBox()
  
  self.activeflag = true
  self.tech = config.getParameter("tech") or "dash"
end

function update(dt)
	if self.activeflag then
		world.sendEntityMessage(effect.sourceEntity(),"techChangeOnBD",self.tech)
		self.activeflag = false
	end
	
end

function uninit()
  --world.sendEntityMessage(effect.sourceEntity(),"techChangeOff")
end
