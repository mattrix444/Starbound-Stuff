require "/scripts/behavior.lua"
require "/scripts/pathing.lua"
require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/drops.lua"
require "/scripts/status.lua"
require "/scripts/companions/capturable.lua"
require "/scripts/tenant.lua"
require "/scripts/staticrandom.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"

-- Engine callback - called on initialization of entity
function init()
  self.pathing = {}

  seed = math.abs(monster.seed())
  math.randomseed(seed)
  
  self.shouldDie = true
  self.notifications = {}
  storage.spawnTime = world.time()
  if storage.spawnPosition == nil or config.getParameter("wasRelocated", false) then
    local position = mcontroller.position()
    local groundSpawnPosition
    if mcontroller.baseParameters().gravityEnabled then
      groundSpawnPosition = findGroundPosition(position, -20, 3)
    end
    storage.spawnPosition = groundSpawnPosition or position
  end

  self.behavior = behavior.behavior(config.getParameter("behavior"), sb.jsonMerge(config.getParameter("behaviorConfig", {}), skillBehaviorConfig()), _ENV)
  self.board = self.behavior:blackboard()
  self.board:setPosition("spawn", storage.spawnPosition)

  self.collisionPoly = mcontroller.collisionPoly()
  
  if animator.hasSound("deathPuff") then
    monster.setDeathSound("deathPuff")
  end
  if config.getParameter("deathParticles") then
    monster.setDeathParticleBurst(config.getParameter("deathParticles"))
  end

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 20))
  mcontroller.setAutoClearControls(false)
  self.behaviorTickRate = config.getParameter("behaviorUpdateDelta", 2)
  self.behaviorTick = math.random(1, self.behaviorTickRate)

  animator.setGlobalTag("flipX", "")
  self.board:setNumber("facingDirection", mcontroller.facingDirection())

  capturable.init()

  -- Listen to damage taken
  self.damageTaken = damageListener("damageTaken", function(notifications)
	
    for _,notification in pairs(notifications) do
      if notification.healthLost > 0 then
        self.damaged = true
        self.board:setEntity("damageSource", notification.sourceEntityId)
      end
	  if animator.hasSound("hurtNoise") and notification.healthLost >= 1 and self.ouchTimer <= 0 then
		animator.playSound("hurtNoise")
		self.ouchTimer = 2.0
	  end
    end
  end)

  self.debug = true

  message.setHandler("notify", function(_,_,notification)
      return notify(notification)
    end)
  message.setHandler("despawn", function()
      monster.setDropPool(nil)
      monster.setDeathParticleBurst(nil)
      monster.setDeathSound(nil)
      self.deathBehavior = nil
      self.shouldDie = true
      status.addEphemeralEffect("monsterdespawn")
    end)

  local deathBehavior = config.getParameter("deathBehavior")
  if deathBehavior then
    self.deathBehavior = behavior.behavior(deathBehavior, config.getParameter("behaviorConfig", {}), _ENV, self.behavior:blackboard())
  end

  self.forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  self.damageSources = ControlMap:new(config.getParameter("damageSources", {}))
  self.touchDamageEnabled = false
  self.supsd = false
  self.supstun = false
  sb.logInfo("supstun initialized to false")
  sb.logInfo("Current value of supstun: " .. tostring(self.supstun))

  if config.getParameter("elite", false) then
    status.setPersistentEffects("elite", {"elitemonster"})
  end

  if config.getParameter("damageBar") then
    monster.setDamageBar(config.getParameter("damageBar"));
  end

  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  self.ouchTimer = 0
  
  if config.getParameter("supCloned", false) == true then
      monster.setDropPool(nil)
  end
  
  
  sb.logInfo(sb.print(config.getParameter("supProcedural", false)))
  sb.logInfo(sb.print(config.getParameter("supMiniboss", false)))
  sb.logInfo(sb.print(config.getParameter("supFlying", false)))
  
  local suppowm = 0.6 + 0.8 * math.random()
  --monster.lua is used to randomize monsters because the monster spawning function is hardcoded
  --check to see if the monster has been randomised yet. If not, generate a set of parameters using the seed
  --for custom monsters to skip this, add '"supSecond": false' to your parameters
  if config.getParameter("supSecond", false) == false then
	if config.getParameter("supProcedural", false) then
		local supparams = suppara(suppowm)
		--spawn new monster using new parameters
		world.spawnMonster(monster.type(), mcontroller.position(), supparams)
		
		--remove the original monster
		monster.setDropPool(nil)
		monster.setDeathParticleBurst(nil)
		monster.setDeathSound(nil)
		self.deathBehavior = nil
		self.shouldDie = true
		status.setPrimaryDirectives(string.format("?multiply=ffffff%02x", 0))
		status.setResource("health", 0)
		mcontroller.translate({0, -100000})
		return
	end
  end
  
  if config.getParameter("supProcedural", false) then
	if config.getParameter("supSecond", false) == true and #status.getPersistentEffects("monster") == 0 then
	  if not config.getParameter("monsterTypeName") then -- Compatibility with Pet Naming Station
	    monster.setName(supname())
	  end
	  supstats(suppowm)
	elseif config.getParameter("supSecond", false) == true then
	  if not config.getParameter("monsterTypeName") then -- Compatibility with Pet Naming Station
		monster.setName(supname())
	  end
	end
  end
end

function suppara(suppowm)
		local isranged = false
		
		--stupid access violations
		
		local supparams = monster.uniqueParameters()
		supparams.supSecond = true
		supparams.seed = monster.seed()
		supparams.aggressive = config.getParameter("aggressive", true)
		supparams.level = monster.level()
		
		supparams.behaviorConfig = {}
		supparams.skillCount = supparams.skillCount or config.getParameter("skillCount", 1)
		supparams.baseSkills = supparams.baseSkills or config.getParameter("baseSkills", {})
		supparams.specialSkills = supparams.specialSkills or config.getParameter("specialSkills", {})
		supparams.touchDamage = supparams.touchDamage or config.getParameter("touchDamage", {})
		supparams.movementSettings = supparams.movementSettings or config.getParameter("movementSettings", {})
		
		--give ranged attacks to monsters
		if math.random(3) == 1 or config.getParameter("supMiniboss", false) then
			local rangedattacks = { "acidicSpitAttack", "acidSprayAttack", "beamBurstAttack", "beetleSwarmAttack", "bloodVomitAttack", "blueFlameAttack", "boneRainAttack", "bubbleBlastAttack", "burninghaloAttack", "cellBlastAttack", "darkGasAttack", "darkGravityBallAttack", "doubleBarbSprayAttack", "explosivePhlegmAttack", "eyeballShotAttack", "eyeballSprayAttack", "fireballAttack", "fireSwirlAttack", "fishBreathAttack", "flameBurstAttack", "flySwarmAttack", "gasBelchAttack", "glitterAttack", "iceBlastAttack", "iceShotAttack", "inkSprayAttack", "leafyGustAttack", "lightBallAttack", "miniDragonBreathAttack", "mudBallAttack", "orbOfZotsAttack", "plasmaSweepAttack", "plasmaTorpedoAttack", "putridWaveAttack", "rainbowVomitAttack", "rangedChompAttack", "rockRollAttack", "rockShotAttack", "seedSpitAttack", "shardSprayAttack", "shockingBoltAttack", "shockingWaveAttack", "smokeRingAttack", "snotBubbleAttack", "snotShotAttack", "sonicWaveAttack", "spiceCloudAttack", "staticDischargeAttack", "tentacleShotAttack", "waterGunAttack", "barbSprayAttack", "bioCritterAttack", "darkPlasmaAttack", "electricCloudAttack", "fireCloudAttack", "iceCloudAttack", "lightGravityBallAttack", "lightningAttack", "mightyRoarAttack", "moontantGoopAttack", "plasmaBallAttack", "plasmaBurstAttack", "poisonCloudAttack", "poopBreathAttack", "smoglinGasAttack", "snauntSpitAttack", "snuffishSpitAttack", "spinSlashAttack", "tarBallAttack", "twistingPulseAttack", "volcanoAttack", "webShotAttack", "heatedPlasmaAttack", "boulderRollAttack", "boulderShotAttack", "explosiveJellyAttack", "gravityBallAttack", "orbOfZotsAttack2", "rockShardAttack", "waterGunAttack2", "bioLightAttack", "bloodCloudAttack", "coralShardAttack", "heckBloodAttack", "hypnoOrbAttack", "iceBurstAttack", "lightningBurstAttack", "poisonBurstAttack", "slimeBlobAttack"}
			local chosenranged = rangedattacks[math.random(#rangedattacks)]
			supparams.skillCount = supparams.skillCount + 1
			isranged = true
			table.insert(supparams.specialSkills, chosenranged)
		end
		
		--give dashes to monsters
		if math.random(6) == 1 then
			local rangedattacks = {}
			if config.getParameter("supFlying", false) then
				rangedattacks = { "supFlyDodge1a", "supFlyDodge1b", "supFlyDodge1c", "supFlyDodge1d", "supFlyDodge2a", "supFlyDodge2b", "supFlyDodge2c", "supFlyDodge2d", "supFlyDodge3a", "supFlyDodge3b", "supFlyDodge3c", "supFlyDodge3d" }
			else
				rangedattacks = { "supDashDodge1a", "supDashDodge1b", "supDashDodge1c", "supDashDodge1d", "supDashDodge2a", "supDashDodge2b", "supDashDodge2c", "supDashDodge2d", "supDashDodge3a", "supDashDodge3b", "supDashDodge3c", "supDashDodge3d" }
			end
			local chosenranged = rangedattacks[math.random(#rangedattacks)]
			supparams.skillCount = supparams.skillCount + 1
			table.insert(supparams.baseSkills, chosenranged)
		end
		
		--give block ability to monsters
		if math.random(30) == 1 then
			supparams.skillCount = supparams.skillCount + 1
			table.insert(supparams.baseSkills, "supGuard")
		end
		
		--give special abilities to monsters
		if math.random(6) == 1 or config.getParameter("supMiniboss", false) then
			local rangedattacks = {  }
			if not config.getParameter("supFlying", false) then
				rangedattacks = { "supAbsorb", "supAdapt", "supAid", "supArc", "supAttract", {"supAura", "supAura", "supAura", "supAura", "supAura2", "supAura3", "supAura4", "supAura5"}, "supBarrier", {"supBeam", "supBeam", "supBeam", "supBeam", "supBeam2", "supBeam3", "supBeam4", "supBeam5"}, "supBerserk", "supBlink", "supBlock", "supBlood", "supBlossom", {"supBoom", "supBoom", "supBoom", "supBoom", "supBoom2", "supBoom3", "supBoom4", "supBoom5"}, "supBounce", "supBreak", "supBubble", {"supCage", "supCage2", "supCage3", "supCage4"}, "supCircle", "supCloak", {"supCloud", "supCloud2", "supCloud3", "supCloud4"}, "supCurse", "supDagger", "supDam", "supDash", "supDecay", "supDeflect", "supDodge", "supDoom", "supDrain", "supDrill", {"supFlip", "supFlip2", "supFlip3", "supFlip4"}, "supForce", "supFortify", "supFury", "supGate", "supGhost", "supGlow", {"supGrab", "supGrab2", "supGrab3", "supGrab4"}, "supGrav", "supGust", "supHook", "supHop", "supHope", {"supHuge", "supHuge", "supHuge", "supHuge", "supHuge2", "supHuge3", "supHuge4", "supHuge5"}, "supIcicle", {"supIrradiate", "supIrradiate2", "supIrradiate3", "supIrradiate4"}, "supJump", "supKb", "supLeech", "supLevitate", "supLightningRod", "supMend", "supMetal", {"supMine", "supMine2", "supMine3", "supMine4"}, "supMist", "supNether", {"supNova", "supNova2","supNova3", "supNova4"}, "supOne", "supParry", {"supPillar", "supPillar", "supPillar", "supPillar", "supPillar2", "supPillar3", "supPillar4", "supPillar5"}, {"supPlague", "supPlague2",  "supPlague3", "supPlague4"}, {"supPortal", "supPortal2", "supPortal3", "supPortal4"}, "supProtect", "supPull", "supRage", "supRaze", "supReactive", "supRecall", "supRecovery", "supReflect", "supRegenerate", "supRise", "supRocket", "supRod", "supRoll", "supRun", "supSap", "supSeek", "supShadow", "supShield", "supShieldFast", "supShieldLeech", "supShieldRegen", "supSlam", {"supSnare", "supSnare2", "supSnare3", "supSnare4"}, "supSoul", {"supSpikes", "supSpikes2", "supSpikes3", "supSpikes4"}, "supSpin", "supSteal", "supStick", {"supStomp", "supStomp", "supStomp", "supStomp", "supStomp2", "supStomp3", "supStomp4", "supStomp5"}, "supStone", {"supStrike", "supStrike2", "supStrike3", "supStrike4"}, {"supSwarm", "supSwarm2", "supSwarm3", "supSwarm4"}, "supTemp", {"supThorn", "supThorn2", "supThorn3", "supThorn4"}, "supTime", "supToss", {"supTrail", "supTrail2", "supTrail3", "supTrail4"}, "supTripleJump", "supUnkillable", {"supWaterWave", "supWaterWave", "supWaterWave", "supWaterWave", "supWaterWave2", "supWaterWave3", "supWaterWave4", "supWaterWave5"}, "supWhip", "supWhirl", "supWind", "supWrath", { "supZone", "supZone2", "supZone3", "supZone4"}, "supRag", "supReg", "supRus", "supEnd", "supBin", "supBin2", "supBin3", "supBin4", "supAgile", "supBrace", "supCob", "supFix", "supPro", "supSalt", "supSneak", "supTether", "supZappy", "supGift", "supBar", "supCha", "supCle", "supDra", "supEgg", "supFad", "supFue", "supGla", "supGro", "supHol", "supHor", "supLif", "supNeb", "supOrb", "supPic", "supPin", "supPyl", "supRet", "supSac", "supSee", "supShr", "supSil", "supSta", "supSwa", "supTur", "supVam", "supWoo", "supXax", "supAst", "supFrobur", "supHot", "supKit", "supPal", "supRep", "supVuln", "supDro", "supFla", "supSho", "supWeb", "supAlo", "supApe", "supLon", "supPac", "supChase", "supChas", "supWar", "supPor", {"supClone", "supClone2", "supClone3", "supClone4"} }
			else
				  rangedattacks = { "supAbsorb", "supAdapt", "supAid", "supArc", "supAttract", {"supAura", "supAura", "supAura", "supAura", "supAura2", "supAura3", "supAura4", "supAura5"}, "supBarrier", {"supBeam", "supBeam", "supBeam", "supBeam", "supBeam2", "supBeam3", "supBeam4", "supBeam5"}, "supBerserk", "supBlink", "supBlock", "supBlood", "supBlossom", {"supBoomSwoop", "supBoomSwoop", "supBoomSwoop", "supBoomSwoop", "supBoomSwoop2", "supBoomSwoop3", "supBoomSwoop4", "supBoomSwoop5"}, "supBounce", "supBreak", "supBubble", {"supCage", "supCage2", "supCage3", "supCage4"}, "supCircle", "supCloak", {"supCloud", "supCloud2", "supCloud3", "supCloud4"}, "supCurse", "supDagger", "supDam", "supDecay", "supDeflect", "supDoom", "supDrain", "supDrill", "supForce", "supFortify", "supFury", "supGate", "supGhost", "supGlow", "supGrav", "supGust", "supHook", "supHope", "supIcicle", {"supIrradiate", "supIrradiate2", "supIrradiate3", "supIrradiate4"}, "supKb", "supLeech", "supLevitate", "supLightningRod", "supMend", "supMetal", {"supMine", "supMine2", "supMine3", "supMine4"}, "supMist", "supNether", {"supNova", "supNova2","supNova3", "supNova4"}, "supOne", "supParry", {"supPillar", "supPillar", "supPillar", "supPillar", "supPillar2", "supPillar3", "supPillar4", "supPillar5"}, {"supPlague", "supPlague2",  "supPlague3", "supPlague4"}, {"supPortal", "supPortal2", "supPortal3", "supPortal4"}, "supProtect", "supRage", "supReactive", "supRecall", "supRecovery", "supReflect", "supRegenerate", "supRod", "supRun", "supSap", "supSeek", "supShadow", "supShield", "supShieldFast", "supShieldLeech", "supShieldRegen", {"supSnare", "supSnare2", "supSnare3", "supSnare4"}, "supSoul", {"supSpikes", "supSpikes2", "supSpikes3", "supSpikes4"}, "supSteal", "supStick", {"supStompDive", "supStompDive", "supStompDive", "supStompDive", "supStompDive2", "supStompDive3", "supStompDive4", "supStompDive5"}, "supStone", {"supStrike", "supStrike2", "supStrike3", "supStrike4"}, {"supSwarm", "supSwarm2", "supSwarm3", "supSwarm4"}, "supTemp", {"supThorn", "supThorn2", "supThorn3", "supThorn4"}, "supTime", {"supTrail", "supTrail2", "supTrail3", "supTrail4"}, "supUnkillable", {"supWaterWave", "supWaterWave", "supWaterWave", "supWaterWave", "supWaterWave2", "supWaterWave3", "supWaterWave4", "supWaterWave5"}, "supWhip", "supWind", "supWrath", { "supZone", "supZone2", "supZone3", "supZone4"}, "supRag", "supReg", "supRus", "supEnd", "supBin", "supBin2", "supBin3", "supBin4", "supAgile", "supBrace", "supCob", "supFix", "supPro", "supSalt", "supSneak", "supTether", "supZappy", "supGift", "supBar", "supCha", "supDra", "supEgg", "supFad", "supFue", "supGla", "supGro", "supHol", "supHor", "supLif", "supNeb", "supOrb", "supPic", "supPin", "supPyl", "supRet", "supSac", "supSee", "supShr", "supSil", "supSta", "supSwa", "supTur", "supVam", "supWoo", "supXax", "supAst", "supFrobur", "supHot", "supKit", "supPal", "supRep", "supVuln", "supDro", "supFla", "supSho", "supWeb", "supAlo", "supApe", "supLon", "supPac", "supChase", "supChas", "supWar", "supPor", {"supClone", "supClone2", "supClone3", "supClone4"} }
			end
			local chosenranged = rangedattacks[math.random(#rangedattacks)]
			if type(chosenranged) == "table" then
				chosenranged = chosenranged[math.random(#chosenranged)]
			end
			supparams.skillCount = supparams.skillCount + 1
			table.insert(supparams.specialSkills, chosenranged)
		end
		
		--randomise the capture health fraction for non-minibosses
		if not config.getParameter("supMiniboss", false) then
		  supparams.captureHealthFraction = math.random() * 0.8 + 0.1
		end
		
		
		local suptoum = 1
		--bunch of monster-specific changes
		if not config.getParameter("supFlying", false) then
			if math.random(10) < 5 then
				local count = 1
				if math.random(4) == 1 then
				  count = 2
				elseif math.random(9) == 1 then
				  count = 3
				end
				for i = 1, count do
				  local rangedattacks = { "supPounceAttack", "supChargeAttack", "supRunAttack" }
				  local chosenranged = rangedattacks[math.random(#rangedattacks)]
				  supparams.skillCount = supparams.skillCount + 1
				  table.insert(supparams.baseSkills, chosenranged)
				end
			end
			
			supparams.supJump = false
			if math.random(2) == 1 then
				supparams.supJump = true
			end
			
			supparams.supDist = 0
			supparams.fleeFar = false
			if math.random(3) == 1 then
				if math.random(5) == 1 then
					supparams.supDist = math.random(5, 25)
					supparams.fleeFar = true
				else
					if isranged == true then
						supparams.supDist = math.random(5, 20)
					else
						supparams.supDist = math.random(4, 5)
					end
				end
			else
				supparams.supDist = math.random(2, 3)
			end
			
			supparams.flee = false
			supparams.fleeReverse = false
			supparams.fleeNorm = false
			supparams.fleeHealth = 0
			if math.random(4) == 1 then	
				if math.random(4) == 1 then
					supparams.flee = true
				elseif math.random(2) == 1 then
					supparams.fleeNorm = true
					if not config.getParameter("supMiniboss", false) then
					  supparams.fleeHealth = supparams.captureHealthFraction
					else
					  supparams.fleeHealth = math.random()
					end
				else
					supparams.fleeReverse = true
					if not config.getParameter("supMiniboss", false) then
					  supparams.fleeHealth = supparams.captureHealthFraction
					else
					  supparams.fleeHealth = math.random()
					end
				end
			end
			local supmelee = ""
			if math.random(10) ~= 1 then
				if math.random(2) == 1 then
					supmelee = "supMeleeAttack"
				elseif math.random(3) == 1 then
					supmelee = "supMeleeAttack2"
					suptoum = 0.75
				elseif math.random(2) == 1 then
					supmelee = "supMeleeAttack3"
					suptoum = 1.25
				else
					supmelee = "supMeleeAttack4"
				end
			elseif math.random(2) == 1 then
				supmelee = "supMeleeAttack5"
				suptoum = 0.75
			else
				supmelee = "supMeleeAttack6"
				suptoum = 1.25
			end
			table.insert(supparams.baseSkills, 1, supmelee)
			supparams.skillCount = supparams.skillCount + 1
		elseif config.getParameter("supFlying", false) then
			supparams.flyRange = math.random(6, 20)
			if monster.type() == "largeflying" or monster.type() == "suplargeflyingminiboss" then
				supparams.flyRange = supparams.flyRange + 4
			end
			if math.random(4) == 1 then
				local meleeAttacks = {"flyingChargeAttack", "flyingSwoopAttack4", "flyingDiveAttack"}
				local attackcount = 1
				if math.random(3) == 1 then
					attackcount = 2
				end
				
				for i = 1, attackcount do
					local numb = math.random(#meleeAttacks)
					local meleeattack = meleeAttacks[numb]
					table.remove(meleeAttacks, numb)
					table.insert(supparams.baseSkills, 1, meleeattack)
				end
				supparams.skillCount = supparams.skillCount + attackcount
				supparams.flyRange = 2
			else
				local meleeAttacks = {{"flyingChargeAttack", "flyingChargeAttack2", "flyingChargeAttack3"}, {"flyingSwoopAttack4", "flyingSwoopAttack2", "flyingSwoopAttack3"}, {"flyingDiveAttack", "flyingDiveAttack2", "flyingDiveAttack3"}}
				
				local attackcount = 1
				if math.random(8) == 1 then
					attackcount = 3
				elseif math.random(7) <= 3 then
					attackcount = 2
				end
				
				for i = 1, attackcount do
					local numb = math.random(#meleeAttacks)
					local attackcat = meleeAttacks[numb]
					local meleeattack = attackcat[math.random(3)]
					table.remove(meleeAttacks, numb)
					table.insert(supparams.baseSkills, 1, meleeattack)
				end
				supparams.skillCount = supparams.skillCount + attackcount
			end	
			
			supparams.flee = false
			supparams.fleeReverse = false
			supparams.fleeNorm = false
			supparams.fleeHealth = 0
			if math.random(4) == 1 then	
				if math.random(4) == 1 then
					supparams.flee = true
				elseif math.random(2) == 1 then
					supparams.fleeNorm = true
					if not config.getParameter("supMiniboss", false) then
					  supparams.fleeHealth = supparams.captureHealthFraction
					else
					  supparams.fleeHealth = math.random()
					end
				else
					supparams.fleeReverse = true
					if not config.getParameter("supMiniboss", false) then
					  supparams.fleeHealth = supparams.captureHealthFraction
					else
					  supparams.fleeHealth = math.random()
					end
				end
			end
			
			supparams.glideState = "glide"
			supparams.fastState = "flyfast"
			if math.random(2) == 1 then
				supparams.fastState = "fly"
			end
			if math.random(2) == 1 then
				supparams.glideState = "fly"
			end	
			
			supparams.movementSettings.flySpeed = math.random(10, 22)
		end
		
		--aggro range
		supparams.behaviorConfig.targetQueryRange = math.random(5, 65)
		supparams.behaviorConfig.keepTargetInRange = math.max(supparams.behaviorConfig.targetQueryRange + math.random(10, 20), 30)
		if config.getParameter("supMiniboss", false) then
			supparams.behaviorConfig.targetQueryRange = supparams.behaviorConfig.targetQueryRange + 15
			supparams.behaviorConfig.keepTargetInRange = supparams.behaviorConfig.keepTargetInRange + 15
		end
		
		--more color combinations
		if not supparams.colorSwap then
			supparams.colorSwap = {}
			local supcolora = {{"12374E", "176995", "1EA1C6", "54BAF5"}, {"2b3916", "547225", "80b32f", "b6eb5a"}, {"574b38", "81725b", "bdae97", "dfd3c1"}, {"1d6f19", "36a83c", "5ce078", "8affaf"}, {"40196f", "7436a8", "ba5ce0", "e98aff"}, {"19506F", "367ca8", "5c97e0", "8ab3ff"}, {"6f4719", "a87e36", "e0c65c", "fff38a"}, {"6f1936", "a83651", "e05c64", "ff8e8a"}, {"171717", "515151", "767676", "9f9f9f"}, {"11111E", "33333A", "5C5C5E", "898989"}, {"231717", "4C3C35", "766559", "8E7A6C"}, {"4b4b4b", "828282", "b6b6b6", "d9d9d9"}, {"5c5c5c", "a5a5a5", "e6e6e6", "f8f8f8"}, {"652651", "9d418f", "cd5fd2", "d790e9"}, {"39164a", "6d327e", "b14ab2", "e673cd"}, {"742977", "bb4fba", "e884e7", "ffc3fb"}, {"623221", "9f4d29", "d47744", "faba86"}, {"68320d", "a56220", "e48c37", "fad086"}, {"512F42", "854B8E", "bb71bf", "daaadf"}, {"66452E", "A47C56", "D9AA7B", "F7DDB0"}, {"12384E", "176795", "1E88C6", "54BAF5"}, {"6F1936", "b12c4c", "E05C64", "FF8E8A"}, {"5F5B4B", "939070", "C2C2A0", "E5E5D4"}, {"574B38", "81725B", "BDAE97", "DFD3C1"}, {"3A201E", "4D302C", "6E4238", "996555"}, {"693832", "A66859", "DA907E", "F7C9B2"}, {"351819", "69292B", "A4353A", "DB6169"}, {"723522", "B16232", "D99B4A", "DFC171"}, {"443529", "875D3B", "BF8857", "D8B18F"}, {"8F692D", "AB9E40", "E3E25F", "F2F2A9"}, {"156054", "318275", "56A49F", "7EBBC2"}, {"3C4D74", "5F8CC4", "8AC3F2", "B6E4FF"}, {"1E3614", "3A6D30", "6F9F5D", "A0C18C"}, {"171717", "262626", "383838", "4C4C4C"}, {"1C2A33", "344651", "52646D", "7D8B8E"}, {"8C8C8C", "BFBFBF", "E5E5E5", "FBFBFB"}, {"6f2919", "a85636", "e0975c", "ffca8a"}}
			local supcolorb = {{"5F5B4B", "A89C77", "DCCE9C", "FFF0C4"}, {"2d506b", "4787b3", "63aee4", "91dcff"}, {"7F6D52", "BFA27A", "EFD5AB", "F9E6CC"}, {"735e3a", "a38d59", "d9c189", "f7e7b2"}, {"3a7343", "59a36a", "89d99c", "b2f7c7"}, {"73673a", "a39959", "d9cf89", "f7f3b2"}, {"736e3a", "a3a359", "d8d989", "f2f7b2"}, {"3a3e73", "5b59a3", "8b89d9", "b8b2f7"}, {"503224", "965751", "E07F7F", "EFA4AE"}, {"4b4b4b", "828282", "b6b6b6", "d9d9d9"}, {"6c5d22", "b0a747", "e2e189", "f0f0c2"}, {"66452e", "a47c56", "d9aa7b", "f7ddb0"}, {"41546c", "6995b7", "96cbe6", "BFE9FF"}, {"485548", "728473", "acc8ac", "d8e5d6"}, {"455d1e", "839731", "d0dc61", "f5f898"}, {"5f5b4b", "939070", "c2c2a0", "e5e5d4"}, {"5b553d", "b2a025", "e8e63a", "fefebb"}, {"184817", "389042", "71d071", "b7faae"}, {"3A933E", "6DBE3A", "8EEA59", "E8F263"}, {"5C5C5C", "A5A5A5", "E6E6E6", "F8F8F8"}, {"11111E", "33333A", "5C5C5E", "898989"}, {"0E3A2B", "157F45", "61BA61", "A7E278"}, {"6F1936", "A83651", "E05C64", "FF8E8A"}, {"1C2A33", "344651", "52646D", "7D8B8E"}, {"274A65", "3C7CA8", "549FD5", "7DC8EB"}, {"723522", "B16232", "D99B4A", "DFC171"}, {"156054", "318275", "56A49F", "7EBBC2"}, {"8F692D", "AB9E40", "E3E25F", "F2F2A9"}, {"231717", "4C3C35", "766559", "8E7A6C"}, {"974A71", "C686A2", "E5CEE5", "F8F8F8"}, {"1E3614", "3A6D30", "6F9F5D", "A0C18C"}}
			local supcolorc = {{"8C7C00", "C1AF00", "F2DA00", "FFEA4C"}, {"249500", "2ebe00", "35dc00", "3bf300"}, {"69A5D8", "74D2EE", "9BEAFF", "C6F6FF"}, {"950000", "be1b00", "FF3C00", "FF6932"}, {"95004c", "be0060", "FF0083", "FF26BA"}, {"1C2293", "1B4EC4", "3F7CFF", "2BC2FF"}, {"949500", "bbbe00", "d9dc00", "eff300"}, {"953800", "be5000", "DC7C00", "F39B00"}, {"95004a", "be005e", "FF0083", "FF26BA"}, {"954d00", "be6b00", "dc9600", "f3b700"}, {"008595", "00b8be", "00dcda", "00f3df"}, {"171717", "262626", "383838", "4C4C4C"}, {"B02182", "FC45C1", "FF80FF", "FFD6FF"}, {"69A5D8", "74D2EE", "9BEAFF", "C6F6FF"}, {"891400", "D52B00", "FF7400", "FFB632"}, {"5C5C5C", "A5A5A5", "E6E6E6", "F8F8F8"}, {"3A3E73", "5B59A3", "8B89D9", "B8B2F7"}, {"951500", "be1b00", "dc1f00", "f32200"}}
			local suppa = supcolora[math.random(#supcolora)]
			local suppb = supcolorb[math.random(#supcolorb)]
			local suppc = supcolorc[math.random(#supcolorc)]
			supparams.colorSwap["6f2919"] = suppa[1]
			supparams.colorSwap["a85636"] = suppa[2]
			supparams.colorSwap["e0975c"] = suppa[3]
			supparams.colorSwap["ffca8a"] = suppa[4]
			supparams.colorSwap["735e3a"] = suppb[1]
			supparams.colorSwap["a38d59"] = suppb[2]
			supparams.colorSwap["d9c189"] = suppb[3]
			supparams.colorSwap["f7e7b2"] = suppb[4]
			supparams.colorSwap["951500"] = suppc[1]
			supparams.colorSwap["be1b00"] = suppc[2]
			supparams.colorSwap["dc1f00"] = suppc[3]
			supparams.colorSwap["f32200"] = suppc[4]
		end
		

		
		--melee status effects
		if math.random(15) == 1 then
			if math.random(2) == 1 then
				local suptr = math.random(4)
				if suptr == 1 then
					supparams.touchDamage.statusEffects = {{
						effect = "burning",
						duration = 5
					}}
					supparams.touchDamage.damageSourceKind = "fireaxe"
				elseif suptr == 2 then
					supparams.touchDamage.statusEffects = {{
						effect = "frostslow",
						duration = 5
					}}
					supparams.touchDamage.damageSourceKind = "iceaxe"
				elseif suptr == 3 then
					supparams.touchDamage.statusEffects = {{
						effect = "electrified",
						duration = 5
					}}
					supparams.touchDamage.damageSourceKind = "electricaxe"
				else
					supparams.touchDamage.statusEffects = {{
						effect = "weakpoison",
						duration = 5
					}}
					supparams.touchDamage.damageSourceKind = "poisonaxe"
				end
			else
				local suptr = math.random(25)
				if suptr == 1 then
					supparams.touchDamage.statusEffects = {{
						effect = "wet",
						duration = 3
					}}
				elseif suptr == 2 then
					supparams.touchDamage.statusEffects = {{
						effect = "stun",
						duration = 1
					}}
				elseif suptr == 3 then
					supparams.touchDamage.statusEffects = {{
						effect = "lowgrav",
						duration = 2
					}}
				elseif suptr == 4 then
					supparams.touchDamage.statusEffects = {{
						effect = "supdeathbomb",
						duration = 2
					}}
				elseif suptr == 5 then
					supparams.touchDamage.statusEffects = {{
						effect = "bouncy",
						duration = 2
					}}
				elseif suptr == 6 then
					supparams.touchDamage.statusEffects = {{
						effect = "supgk",
						duration = 0.001
					}}
				elseif suptr == 7 then
					supparams.touchDamage.statusEffects = {{
						effect = "runboost",
						duration = 2
					}}
				elseif suptr == 8 then
					supparams.touchDamage.statusEffects = {{
						effect = "suptime",
						duration = 0.4
					}}
				elseif suptr == 9 then
					supparams.touchDamage.statusEffects = {{
						effect = "supvuln",
						duration = 2
					}}
				elseif suptr == 10 then
					supparams.touchDamage.statusEffects = {{
						effect = "supweak",
						duration = 2
					}}
				elseif suptr == 11 then
					supparams.touchDamage.statusEffects = {{
						effect = "suphighgrav",
						duration = 1
					}}
				elseif suptr == 12 then
					supparams.touchDamage.statusEffects = {{
						effect = "supslow2",
						duration = 2
					}}
				elseif suptr == 13 then
					supparams.touchDamage.statusEffects = {{
						effect = "glow",
						duration = 2
					}}
				elseif suptr == 14 then
					supparams.touchDamage.statusEffects = {{
						effect = "supantg",
						duration = 0.4
					}}
				elseif suptr == 15 then
					supparams.touchDamage.statusEffects = {{
						effect = "staffregeneration",
						duration = 2
					}}
				elseif suptr == 16 then
					supparams.touchDamage.statusEffects = {{
						effect = "supbleed",
						duration = 2
					}}
				elseif suptr == 17 then
					supparams.touchDamage.statusEffects = {{
						effect = "supstop2",
						duration = 0.6
					}}
				elseif suptr == 18 then
					supparams.touchDamage.statusEffects = {{
						effect = "supnog",
						duration = 1
					}}
				elseif suptr == 19 then
					supparams.touchDamage.statusEffects = {{
						effect = "supacc",
						duration = 0.001
					}}
				elseif suptr == 20 then
					supparams.touchDamage.statusEffects = {{
						effect = "supcon",
						duration = 1.0
					}}
				elseif suptr == 21 then
					supparams.touchDamage.statusEffects = {{
						effect = "suplav",
						duration = 3.0
					}}
				elseif suptr == 22 then
					supparams.touchDamage.statusEffects = {{
						effect = "supfre",
						duration = 2
					}}
				elseif suptr == 23 then
					supparams.touchDamage.statusEffects = {{
						effect = "supele",
						duration = 2
					}}
				elseif suptr == 24 then
					supparams.touchDamage.statusEffects = {{
						effect = "supbur",
						duration = 2.0
					}}
				elseif suptr == 25 then
					supparams.touchDamage.statusEffects = {{
						effect = "minibossglow",
						duration = 2
					}}
				end
			end
		end
		
		--melee damage and knockback
		supparams.touchDamage.knockback = supparams.touchDamage.knockback * ( 0.5 + math.random())
		supparams.touchDamage.damage = supparams.touchDamage.damage * ( 0.6 + 0.8 * math.random()) / suppowm * suptoum
	return supparams
end

function supname()
	--name generation and simple profanity filter
	local nam = ""
	local nm1 = {"a","e","o","i","u"}
	local nm2 = {"gh","gn","kn","ph","th","tr","tw","wh","wr","chr","bl","br","cl","ch","cr","dr","dw","fl","fr","gl","gr","pl","pr","sl","sm","sn","sp","st","shr","sh","sw","sk","sc","spl","spr","sq","str","scr","sph","thr"}
	local nm3 = {"ch","ck","ct","ff","ft","gh","ll","lse","lm","lk","lt","lf","lve","lch","lge","ld","lb","lp","mb","mp","mph","ph","sh","sk","sp","ss","st","sm","th","zz","dge","tch","ng","nd","nt","nk","nch","nge","nse","pse","pt","mpt","rd","rb","rp","rn","rl","rt","rth","rg","rk","rc","rm","rnt","rld","rst","rx","rse","nx"}
	local nm4 = {"b","c","d","f","g","h","j","k","l","m","n","p","q","r","s","t","v","w","x","z","y"}
	function name1()
		if nam ~= "" and math.random(15) == 1 then return "y" end
		return math.random(4) == 1 and nm1[math.random(#nm1)]..nm1[math.random(#nm1)] or nm1[math.random(#nm1)]
	end
	
	function name2()
		return math.random(4) == 1 and nm2[math.random(#nm2)] or name4()
	end
	
	function name3()
		return math.random(4) == 1 and nm3[math.random(#nm3)] or name4()
	end
	
	function name4()
		return nm4[math.random(#nm4)]
	end
	
	local lenny = math.random(10) == 1 and 4 or math.random(1, 3)
	local ord = math.random(3) == 1
	local erd = false
	
	if lenny == 1 then
		if math.random(2) == 1 then
			ord = true
			erd = false
		else
			erd = true
			ord = false
		end
	end
		
	for i = 1, lenny do
		if ord or math.random(3) == 1 then
			nam = nam..name2()
		end
		nam = nam..name1()
		if erd or math.random(5) <= 3 then
		  local s = name3()
		  nam = nam..s
		  ord = string.sub(s, #s, #s) == 'e'
		else
		  ord = true
		end
	end
	if math.random(10) == 1 then nam = nam.."s" end
	
	return nam:gsub("^%l", string.upper)
end

function supstats(suppowm)
	--we use persistent effects instead of parameter changes to affect the amount of health given to pets by player armor
	status.addPersistentEffects("monster", {{stat = "maxHealth", effectiveMultiplier = 0.8 * math.random() + 0.6}, {stat = "powerMultiplier", effectiveMultiplier = suppowm}})
	if math.random(6) == 1 then
		status.addPersistentEffect("monster", {stat = "supProtection", effectiveMultiplier = 0.93 - 0.28 * math.random()})
	end
	if math.random(6) == 1 then
		if config.getParameter("supMiniboss", false) then
			status.addPersistentEffect("monster", {stat = "healthRegen", amount = status.stat("maxHealth") * (0.008 * math.random() + 0.002)})
		else
			status.addPersistentEffect("monster", {stat = "healthRegen", amount = status.stat("maxHealth") * (0.04 * math.random() + 0.01)})
		end
	end
	
	--elemental resistance
	local elements = {"electric", "fire", "physical", "ice", "poison"}
	local wea = 1
	local str = 1
	
	for i = 1, 8 do
		if math.random(5) == 1 then
			local el = math.random(6)
			if el == 1 then
				wea = wea + 1
			elseif el == 2 then
				str = str + 1
			elseif el == 3 then
				wea = wea - 1
			elseif el == 4 then
				str = str - 1
			end
		end
	end
	
	repeat
		local numb = math.random(#elements)
		local element = elements[numb]
		table.remove(elements, numb)
		if str > 0 then
			str = str - 1
			if element == "physical" then
				status.addPersistentEffect("monster", {stat = "physicalResistance", amount = 0.3 * math.random() + 0.1})
			elseif element == "fire" then
				status.addPersistentEffects("monster", {{stat = "fireResistance", amount = 0.6 * math.random() + 0.2}, {stat = "fireStatusImmunity", amount = 1}})
			elseif element == "poison" then
				status.addPersistentEffects("monster", {{stat = "poisonResistance", amount = 0.6 * math.random() + 0.2}, {stat = "poisonStatusImmunity", amount = 1}})
			elseif element == "ice" then
				status.addPersistentEffects("monster", {{stat = "iceResistance", amount = 0.6 * math.random() + 0.2}, {stat = "iceStatusImmunity", amount = 1}})
			elseif element == "electric" then
				status.addPersistentEffects("monster", {{stat = "electricResistance", amount = 0.6 * math.random() + 0.2}, {stat = "electricStatusImmunity", amount = 1}})
			end
		elseif wea > 0 then
			wea = wea - 1 
			if element == "physical" then
				status.addPersistentEffect("monster", {stat = "physicalResistance", amount = -0.3 * math.random() - 0.1})
			elseif element == "fire" then
				status.addPersistentEffect("monster", {stat = "fireResistance", amount = -0.6 * math.random() - 0.2})
			elseif element == "poison" then
				status.addPersistentEffect("monster", {stat = "poisonResistance", amount = -0.6 * math.random() - 0.2})
			elseif element == "ice" then
				status.addPersistentEffect("monster", {stat = "iceResistance", amount = -0.6 * math.random() - 0.2})
			elseif element == "electric" then
				status.addPersistentEffect("monster", {stat = "electricResistance", amount = -0.6 * math.random() - 0.2})
			end
		end
	until #elements == 0

	
	if entity.damageTeam().type == "enemy" and math.random(10) == 1 then
		monster.setDamageTeam({type = "enemy", team = math.random(0, 10)})
	elseif entity.damageTeam().type == "enemy" and math.random(18) == 1 and not config.getParameter("supMiniboss", false) then
		monster.setDamageTeam({type = "friendly", team = 1})
	end
end

function update(dt)
  monster.setAnimationParameter("suphealth", status.resourcePercentage("health"))
  if config.getParameter("facingMode", "control") == "transformation" then
    mcontroller.controlFace(1)
  end
  
  capturable.update(dt)
  self.damageTaken:update()
  
  
  if self.supsd == true then
    script.setUpdateDelta(1)
	self.behaviorTickRate = 1
	else
	script.setUpdateDelta(20)
  end
  
  if self.ouchTimer > 0 then
    self.ouchTimer = self.ouchTimer - dt
  end

  if status.resourcePositive("stunned") then
    animator.setAnimationState("damage", "stunned")
    animator.setGlobalTag("hurt", "hurt")
    self.stunned = true
	self.supstun = true
    mcontroller.clearControls()
    if self.damaged then
      self.suppressDamageTimer = config.getParameter("stunDamageSuppression", 0.5)
      monster.setDamageOnTouch(false)
    end
    return
  else
    animator.setGlobalTag("hurt", "")
    animator.setAnimationState("damage", "none")
  end

  -- Suppressing touch damage
  if self.suppressDamageTimer then
    monster.setDamageOnTouch(false)
    self.suppressDamageTimer = math.max(self.suppressDamageTimer - dt, 0)
    if self.suppressDamageTimer == 0 then
      self.suppressDamageTimer = nil
    end
  elseif status.statPositive("invulnerable") then
    monster.setDamageOnTouch(false)
  else
    monster.setDamageOnTouch(self.touchDamageEnabled)
  end

  if self.behaviorTick >= self.behaviorTickRate then
    self.behaviorTick = self.behaviorTick - self.behaviorTickRate
    mcontroller.clearControls()

    self.tradingEnabled = false
    self.setFacingDirection = false
    self.moving = false
    self.rotated = false
    self.forceRegions:clear()
    self.damageSources:clear()
    self.damageParts = {}
    clearAnimation()

    if self.behavior then
      local board = self.behavior:blackboard()
      board:setEntity("self", entity.id())
      board:setPosition("self", mcontroller.position())
      board:setNumber("dt", dt * self.behaviorTickRate)
      board:setNumber("facingDirection", self.facingDirection or mcontroller.facingDirection())

      self.behavior:run(dt * self.behaviorTickRate)
    end
    BGroup:updateGroups()

    updateAnimation()

    if not self.rotated and self.rotation then
      mcontroller.setRotation(0)
      animator.resetTransformationGroup(self.rotationGroup)
      self.rotation = nil
      self.rotationGroup = nil
    end

    self.interacted = false
    self.damaged = false
    self.stunned = false
    self.notifications = {}

    setDamageSources()
    setPhysicsForces()
    monster.setDamageParts(self.damageParts)
    overrideCollisionPoly()
  end
  self.behaviorTick = self.behaviorTick + 1
end

function skillBehaviorConfig()
  local skills = config.getParameter("skills", {})
  local skillConfig = {}

  for _,skillName in pairs(skills) do
    local skillHostileActions = root.monsterSkillParameter(skillName, "hostileActions")
    if skillHostileActions then
      construct(skillConfig, "hostileActions")
      util.appendLists(skillConfig.hostileActions, skillHostileActions)
    end
  end

  return skillConfig
end

function interact(args)
  self.interacted = true
  self.board:setEntity("interactionSource", args.sourceId)
end

function shouldDie()
  return (self.shouldDie and status.resource("health") <= 0) or capturable.justCaptured
end

function die()
  if not capturable.justCaptured then
    if self.deathBehavior then
      self.deathBehavior:run(script.updateDt())
    end
    capturable.die()
  end
  spawnDrops()
end

function uninit()
  BGroup:uninit()
end

function setDamageSources()
  local partSources = {}
  for part,ds in pairs(config.getParameter("damageParts", {})) do
    local damageArea = animator.partPoly(part, "damageArea")
    if damageArea then
      ds.poly = damageArea
      table.insert(partSources, ds)
    end
  end

  local damageSources = util.mergeLists(partSources, self.damageSources:values())
  damageSources = util.map(damageSources, function(ds)
    ds.damage = ds.damage * root.evalFunction("monsterLevelPowerMultiplier", monster.level()) * status.stat("powerMultiplier")
    if ds.knockback and type(ds.knockback) == "table" then
      ds.knockback[1] = ds.knockback[1] * mcontroller.facingDirection()
    end

    local team = entity.damageTeam()
    ds.team = { type = ds.damageTeamType or team.type, team = ds.damageTeam or team.team }

    return ds
  end)
  monster.setDamageSources(damageSources)
end

function setPhysicsForces()
  local regions = util.map(self.forceRegions:values(), function(region)
    if region.type == "RadialForceRegion" then
      region.center = vec2.add(mcontroller.position(), region.center)
    elseif region.type == "DirectionalForceRegion" then
      if region.rectRegion then
        region.rectRegion = rect.translate(region.rectRegion, mcontroller.position())
        util.debugRect(region.rectRegion, "blue")
      elseif region.polyRegion then
        region.polyRegion = poly.translate(region.polyRegion, mcontroller.position())
      end
    end

    return region
  end)

  monster.setPhysicsForces(regions)
end

function overrideCollisionPoly()
  local collisionParts = config.getParameter("collisionParts", {})

  for _,part in pairs(collisionParts) do
    local collisionPoly = animator.partPoly(part, "collisionPoly")
    if collisionPoly then
      -- Animator flips the polygon by default
      -- to have it unflipped we need to flip it again
      if not config.getParameter("flipPartPoly", true) and mcontroller.facingDirection() < 0 then
        collisionPoly = poly.flip(collisionPoly)
      end
      mcontroller.controlParameters({collisionPoly = collisionPoly, standingPoly = collisionPoly, crouchingPoly = collisionPoly})
      break
    end
  end
end

function setupTenant(...)
  require("/scripts/tenant.lua")
  tenant.setHome(...)
end
