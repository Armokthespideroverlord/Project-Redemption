function init()
	-- hide unused ui elements
	widget.setText("upgradeCost.itemName", "")
	widget.setText("upgradeCost.itemCount", "")

	-- init variables
	if not self.upgradeState then
		self.upgradeState = {
			upgrading = false,
			startTime = 0,
			endTime = 0,
		}

		self.config = root.assetJson("/interface/scripted/r-platingtable/r-platingtable.config")
		toggleInterface()

		self.itemStorage = {}
		self.upgradeConfig = {}

	end

	self._id = pane.containerEntityId()
	self.upgradeRPC = world.sendEntityMessage(self._id, "r_UpgradeGet")
end

function update(dt)
	-- update the current inventory list
	self.itemStorage = widget.itemGridItems("itemGrid")

	-- ask if we were upgrading
	if (self.upgradeRPC and self.upgradeRPC:finished()) then
		self.upgradeState = self.upgradeRPC:result()[1]
		self.upgradeConfig = self.upgradeRPC:result()[2]

		widget.setItemSlotItem("lockeditemGrid", self.itemStorage[1])
		switchUpgradeMode(self.upgradeState.upgrading)
		self.upgradeRPC = nil
	end

	if self.upgradeState.upgrading == true then
		-- show the upgrade time remaining.
		local timeLeft = os.difftime(self.upgradeState.endTime, os.time())
		if timeLeft < 60 then
			widget.setText("upgradeSlot.timer", string.format("%ds", timeLeft))
		else
			widget.setText("upgradeSlot.timer", string.format("%dm %ds", math.floor(timeLeft / 60), timeLeft % 60))
		end

		-- Handle a completed upgrade
		if os.time() >= self.upgradeState.endTime then
			-- HOLY SHIT UPGRADE THE ITEM
			local newItem = self.itemStorage[1]
			newItem.parameters.level = self.upgradeConfig.newLevel
			-- updates the rarity of the item
			if newItem.parameters.level >= 6 then
				newItem.parameters.rarity = "legendary"
			end

			world.containerTakeAll(self._id)
			world.containerAddItems(self._id, newItem)
			self.upgradeState.upgrading = false
			toggleInterface(newItem)

			-- restore the itemgrid:
			switchUpgradeMode(false)
		end
	end

	-- check if item in slot
	if not self.itemStorage[1] then
		toggleInterface()
		self.hasValidItem = false
	else
		if not self.hasValidItem then
			-- check the item type among other things.
			local name = self.itemStorage[1].name
			for _,v in pairs(self.config.validItems.base) do
				if string.find(name, v) then
					-- valid item inserted switch flag.
					self.hasValidItem = true
					toggleInterface(self.itemStorage[1])
					return
				end
			end
			-- the item actually isn't valid, clear the interface
			toggleInterface()
		end
	end
end


function uninit()
	-- give the player back their item if we're not upgrading it.
	if self.upgradeState.upgrading == false and self.itemStorage[1] then
		local item = self.itemStorage[1]
		world.containerTakeAll(self._id)
		player.giveItem(item)
		self.upgradeConfig = nil
		self.upgradeState = nil
	end
	world.sendEntityMessage(self._id, "r_UpgradeSet", self.upgradeState, self.upgradeConfig)
end


function toggleInterface(item)
	if not item then
		--widget.setVisible("baseStats", false)
		--widget.setVisible("upgradeStats", false)
		widget.setVisible("upgradeCost.currencyCost", false)
		widget.setButtonEnabled("upgradeBtn", false)
		widget.setText("upgradeCost.itemName", "")
		widget.setText("upgradeCost.itemCount", "")
		widget.setItemSlotItem("upgradeCost.itemSlot", {name=""})

		switchUpgradeMode(self.upgradeState.upgrading)
		return
	else
		if not item.parameters.level then
			item.parameters.level = 6
		end
		if item.parameters.level >= 5 then
			widget.setVisible("upgradeCost.currencyCost", false)
		end

		local maxLevel = 6
		-- if frackin'universe is loaded
		if root.itemConfig({name = "weaponupgradeanvil2", count = 1}) then
			maxLevel = 6
		end

		if item.parameters.level >= maxLevel then
			widget.setItemSlotItem("upgradeCost.itemSlot", {name=""})
			widget.setText("upgradeCost.itemName", "MAX LEVEL!")
			widget.setVisible("upgradeCost.currencyCost", false)
			widget.setText("upgradeCost.itemCount", "")
			widget.setButtonEnabled("upgradeBtn", false)
			return
		end
		--widget.setVisible("baseStats", true)
		--widget.setVisible("upgradeStats", true)
		widget.setButtonEnabled("upgradeBtn", true)
		local weapontype = ""

		for _,v1 in pairs({"headwear", "chestwear", "legwear"}) do
			for _, v2 in pairs(self.config.validItems[v1]) do
				if string.find(item.name, v2) then
					calculateUpgrade(item, v1)
				end
			end
		end
	end
end

function switchUpgradeMode(currentState)
	widget.setVisible("lockeditemGrid", currentState)
	if currentState == false then
		widget.setItemSlotItem("lockeditemGrid", {name = ""})
	end

	widget.setVisible("padlock", currentState)
	widget.setVisible("itemGrid", not currentState)
	widget.setVisible("upgradeBtn", not currentState)
	widget.setVisible("stopBtn", currentState)
	widget.setVisible("upgradeSlot.timer", currentState)
end


function calculateUpgrade(item, wepType)
	if not self.hasValidItem then return end

	-- get item params for upgrading
	local itemLvl = item.parameters.level
	self.upgradeConfig = {}

	-- find our pos in the upgrade chart
	for _,v in pairs(self.config.upgradeCosts) do
		if (v.level >= itemLvl) and
		   (v.weaponType == "any" or v.weaponType == wepType) then
			self.upgradeConfig = v;
			break
		end
	end

	-- sanity checking:
	if (not self.upgradeConfig.material) and (not self.upgradeConfig.materialAmount) then
		error("missing upgrade material or amount.")
	end

	-- cache important thingers.
	local upgradeItemDesc = root.itemConfig({name = self.upgradeConfig.material})
	local playerItemCount = player.hasCountOfItem({name = self.upgradeConfig.material})
	local playerCurrencyCount = player.currency("essence")

	-- populate UI
	widget.setItemSlotItem("upgradeCost.itemSlot", {name = self.upgradeConfig.material})
	widget.setText("upgradeCost.itemName", upgradeItemDesc.config.shortdescription)
	widget.setText("upgradeCost.itemCount", playerItemCount .. "/" .. self.upgradeConfig.materialAmount)
	if playerItemCount < self.upgradeConfig.materialAmount then
		widget.setFontColor("upgradeCost.itemCount", "red")
		if not player.isAdmin() then
			widget.setButtonEnabled("upgradeBtn", false)
		end
	else
		widget.setFontColor("upgradeCost.itemCount", "white")
	end

	-- populate currency UI if needed:
	if self.upgradeConfig.currencyNeeded > 0 then
		widget.setText("upgradeCost.currencyCost.text", self.upgradeConfig.currencyNeeded)
		if playerCurrencyCount < self.upgradeConfig.currencyNeeded then
			widget.setFontColor("upgradeCost.currencyCost.text", "red")
			if not player.isAdmin() then
				widget.setButtonEnabled("upgradeBtn", false)
			end
		else
			widget.setFontColor("upgradeCost.currencyCost.text", "white")
		end
	end
end

function stopBtn()
	-- stop upgrade process
	if not self.upgradeState.upgrading then return end

	self.upgradeState = {
		upgrading = false,
		startTime = 0,
		endTime = 0,
	}
	switchUpgradeMode(false)

	-- give the player their items back
	if not self.upgradeConfig then return end
	player.giveItem({name = self.upgradeConfig.material, count = self.upgradeConfig.materialAmount})
	player.addCurrency("essence", self.upgradeConfig.currencyNeeded)
end


function upgradeBtn()
	if not self.hasValidItem then return end
	if not self.upgradeConfig then return end

	-- take items from player's inventory:
	local consumed = false
	if not player.isAdmin() then
		consumed = player.consumeItem({name = self.upgradeConfig.material, count = self.upgradeConfig.materialAmount})
		-- consume currency
		if self.upgradeConfig.currencyNeeded > 0 then
			consumed = player.consumeCurrency("essence", self.upgradeConfig.currencyNeeded)
		end
		-- couldn't consume items, don't upgrade
		if consumed == false then return end
	end
	-- mark upgrade as started
	self.upgradeState.startTime = os.time()
	self.upgradeState.endTime = self.upgradeState.startTime + self.upgradeConfig.timeNeeded

	-- lock the upgrade slot
	widget.setItemSlotItem("lockeditemGrid", self.itemStorage[1])
	switchUpgradeMode(true)

	-- skip timer in admin mode
	if player.isAdmin() then
		self.upgradeState.endTime = os.time()
	end

	self.upgradeState.upgrading = true
end
