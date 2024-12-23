require "/scripts/staticrandom.lua"

origbl3healthinit = init
function init()
	self.supfollow = 0 --Prevent NPC shield's bar from spawning
	origbl3healthinit()
	
	message.setHandler("getBl3Health", getBl3Health)
	message.setHandler("getBl3HealthImages", getBl3HealthImages)
	
	self.healthbarnames = root.assetJson("/scripts/bl3healthconfig/healthbarnames.config")
	self.monsterconfigs = root.assetJson("/scripts/bl3healthconfig/monsterconfigs.config")
	self.bl3healthonce = false 
	
	math.randomseed(math.floor(monster.seed() or 1))
	
	
	if not self.damageTaken then
		-- Listen to damage taken
	  self.damageTaken = damageListener("damageTaken", function(notifications)
		for _,notification in pairs(notifications) do
		  if notification.healthLost > 0 then
			self.damaged = true
			self.board:setEntity("damageSource", notification.sourceEntityId)
		  end
		end
	  end)
  end
end

origbl3healthupadte = update
function update(dt)
	--Don't change healthbar's orientation
	monster.setAnimationParameter("bl3healthbar", status.resourcePercentage("health"))
	if config.getParameter("facingMode", "control") == "transformation" then
		mcontroller.controlFace(1)
	end
	if origbl3healthupadte ~= nil then
		local success, err = pcall(origbl3healthupadte, dt)
		if success then
			sb.logInfo("origbl3healthupadte executed successfully.")
		else
			sb.logError("Error in origbl3healthupadte: %s", err)
		end
	else
		sb.logWarn("origbl3healthupadte is nil, skipping call.")
	end
	if not self.bl3healthonce and world.getProperty("bl3HealthAllRandom") ~= nil and world.getProperty("bl3healthbossRandom") ~= nil then
		self.bl3healthonce = true
		if world.threatLevel() < 1 or world.getProperty("nonCombat") then return end
		local etype = world.entityTypeName(entity.id())
		if not self.healthbarnames then --There is a mod that overwrites the init and loads after mine, but it doesn't overwrite the update, so I'll put this as a safety
			self.healthbarnames = root.assetJson("/scripts/bl3healthconfig/healthbarnames.config")
			self.monsterconfigs = root.assetJson("/scripts/bl3healthconfig/monsterconfigs.config")
			math.randomseed(math.floor(monster.seed()))
		end
		local combination = {"flesh"}
		local percs = {1}
		local excluded = false
		
		--Check if it should use boss style bar
		self.isBoss = self.monsterconfigs.isBoss[etype] or false
		if not self.isBoss then
			for word,_ in pairs(self.monsterconfigs.isBossWords) do
				if string.find(etype,word) then self.isBoss = true break end
			end
		end
		
		--ExcludeCompletely
		if self.monsterconfigs.fullyExcluded[etype] then return end
		for _,word in pairs(self.monsterconfigs.fullyExcludedWords) do
			if string.find(etype,word) then return end
		end
		
		--Exclude desired monsters in config
		if self.monsterconfigs.excludedTypes[etype] or world.getProperty("bl3disabled",false) then excluded = true end 
		if not excluded then
			for _,word in pairs(self.monsterconfigs.excludedWords) do
				if string.find(etype,word) then excluded = true break end
			end
		end
		if not excluded then
			if etype == "punchy" or not world.getProperty("bl3HealthAllRandom",false) or (self.isBoss and not world.getProperty("bl3healthbossRandom",false)) then
				--Select specific monster config or default
				local selectedConfig = "default"
				selectedConfig = (self.monsterconfigs.monsterconfigs[etype] and etype) or selectedConfig --Select custom monstertype config or default
				if selectedConfig == "default" then 
					for word,config in pairs(self.monsterconfigs.wordMonsterConfigs) do
						if string.find(etype,word) then 
							selectedConfig = config
							break 
						end
					end
				end
				if selectedConfig == "default" then
					selectedConfig = status.statusProperty("targetMaterialKind","default")
				end
				selectedConfig = root.assetJson("/scripts/bl3healthconfig/monsterconfig/"..selectedConfig..".config") 
				selectedConfig = selectedConfig.combinations
				
				
				--Select combination config or default
				local combinationConfig = "default"
				local chance = math.random()
				for _,comb in pairs(selectedConfig) do
					if chance <= comb[1] then 
						combinationConfig = comb[2] 
						break
					end
				end
				combinationConfig = root.assetJson("/scripts/bl3healthconfig/combinations/"..combinationConfig..".config")
				combinationConfig = combinationConfig.bars
				
				--Select sepecific combination from combination config
				chance = math.random()
				for _,comb in pairs(combinationConfig) do
					if chance <= comb[1] then 
						combination = comb[2]  
						break
					end
				end
			end
			--If the player allows for randomized healthbars instead of per-config
			if ((not self.isBoss and etype ~= "punchy" and world.getProperty("bl3HealthAllRandom",false)) or (self.isBoss and world.getProperty("bl3healthbossRandom",false))) then
				combination = {}
				math.randomseed(math.floor(monster.seed()))
				local seed = math.random(1, 4294967295)
				local totalBars = randomIntInRange({1, world.getProperty("bl3HealthMaxBars",10)}, seed, "Random bars")
				local types = self.isBoss and self.monsterconfigs.randomBossHealthTypes or self.monsterconfigs.randomHealthTypes
				local i = 1
				
				for i = 1,totalBars,1 do
					seed = math.random(1, 4294967295)
					combination[i] = types[randomIntInRange({1, #types}, seed, "Hail")]
					percs[i] = 1
				end
			end
			
			--Clean combination from non-existing health types adn limit according to user config
			local maxBars = world.getProperty("bl3HealthMaxBars",10)
			for i,healthType in pairs(combination) do
				if i > maxBars then
					combination[i] = nil
				elseif not self.healthbarnames.healthbarnames[healthType] then 
					combination[i] = "default" 
				end
				percs[i] = 1
			end
		end
		
		status.setStatusProperty("maxHealthBars",#combination)
		status.setStatusProperty("currHealthBar",#combination)
		local healthMultiplier = #combination * (1 + world.getProperty("bl3HealthNPCmultiplier",0.0))
		local maxHealth = status.stat("maxHealth") * healthMultiplier
		status.setStatusProperty("healthBarMaxHealth",maxHealth)
		status.setStatusProperty("healthBarHealth",maxHealth)
		status.setStatusProperty("currBl3Percs",percs)
		status.setStatusProperty("bl3healthBars",combination)
		local images = {}
		for i,healthType in pairs(combination) do
			images[i] = root.assetJson("/scripts/bl3healthconfig/healthbarconfig/"..healthType..".config")["image"]
		end
		status.setStatusProperty("bl3healthBarsImages",images)
		if self.isBoss then status.setStatusProperty("isBossBL3",true) end
		--status.addEphemeralEffects({{effect = "monsterHealthBarManager", duration = 100000}})
		
		--Create the healthbar
		--if not self.supfollow then
			if self.isBoss and not self.monsterconfigs.isNotBoss[etype] then
				pcall(function() 
					self.supfollow = world.spawnMonster("bl3healthbar_boss", entity.position(), {bl3healthbarEntityId = entity.id()})
				end)
			else
				pcall(function() 
					self.supfollow = world.spawnMonster("bl3healthbar", entity.position(), {bl3healthbarEntityId = entity.id()})
				end)
			end
		--end
		status.setStatusProperty("bl3_healthbarId",self.supfollow)
		
		self.healthbarnames = nil
	    self.monsterconfigs = nil
	end
	
	--Helps with entities that may have a very low health, like float errors and negative zero
	if status.resourcePercentage("health", 0) <= 0.001 and (self.shouldDie or self.dead) then
		 status.setStatusProperty("healthBarHealth", 0)
		 status.setResource("health", 0)
	end
end

function getBl3Health()
	return { status.resource("health"),status.resourceMax("health"), percs = status.statusProperty("currBl3Percs",{1,1,1,1,1,1,1,1,1,1}), invulnerable = status.stat("invulnerable",0)==1, shield={status.statusProperty("maxDamageAbsorption",0)>0,status.statusProperty("damageAbsorption",0),status.statusProperty("maxDamageAbsorption",0)} }
end

function getBl3HealthImages()
	return { images = status.statusProperty("bl3healthBarsImages"), overlay = status.statusProperty("shieldOverlay")}
end
