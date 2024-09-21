--
-- Please see the license.html file included with this distribution for
-- attribution and copyright information.
--

-- The only reason I have to make an entire new workflow is because I don't want the unconscious
-- status being applied to units. Since that bit of code is in the middle of a huge function, and I
-- don't want to copy/re-implement hte whole function, I'm going to branch it, so units
-- are dealt damage here, while pcs/npcs are dealt damage per the ActionDamage.applyDamage function

local fGetRoll;
local fApplyDmgEffectsToModRoll;
local fHandleApplyDamage;
local fApplyDamage;
local fGetDamageAdjust;

function onInit()
	fGetRoll = ActionDamage.getRoll;
	ActionDamage.getRoll = getRoll;

	fApplyDmgEffectsToModRoll = ActionDamage.applyDmgEffectsToModRoll;
	ActionDamage.applyDmgEffectsToModRoll = applyDmgEffectsToModRoll;

	ActionsManager.registerTargetingHandler("damage", onTargeting);

	fApplyDamage = ActionDamage.applyDamage;
	ActionDamage.applyDamage = applyDamage;

	fGetDamageAdjust = ActionDamage.getDamageAdjust;
	ActionDamage.getDamageAdjust = getDamageAdjust;
end

function getRoll(rActor, rAction)
	local rRoll = fGetRoll(rActor, rAction);

	-- Add in a clause for automatic target handling
	if rAction.target or "" ~= "" then
		rRoll.sDesc = rRoll.sDesc .. "[TARGET:" .. rAction.target .. "]";
	end

	return rRoll;
end

function applyDmgEffectsToModRoll(rRoll, rSource, rTarget)
	fApplyDmgEffectsToModRoll(rRoll, rSource, rTarget);

	if ActorManagerKw.isUnit(rSource) then
		local sAttack = rRoll.sDesc:match("Attack");
		local sPower = rRoll.sDesc:match("Power");

		local sTag = "";
		if sAttack then
			sTag = "ATKDMG"
		elseif sPower then
			sTag = "POWDMG"
		end

		local tDmgEffects, nDmgEffects = EffectManager5E.getEffectsBonusByType(rSource, sTag, true, {}, rTarget);
		if nDmgEffects > 0 then
			local sEffectBaseType = "";
			if #(rRoll.clauses) > 0 then
				sEffectBaseType = rRoll.clauses[1].dmgtype or "";
			end

			for _,v in pairs(tDmgEffects) do
				local bCritEffect = false;
				local aEffectDmgType = {};
				local aEffectSpecialDmgType = {};
				for _,sType in ipairs(v.remainder) do
					if StringManager.contains(DataCommon.specialdmgtypes, sType) then
						table.insert(aEffectSpecialDmgType, sType);
						if sType == "critical" then
							bCritEffect = true;
						end
					elseif StringManager.contains(DataCommon.dmgtypes, sType) then
						table.insert(aEffectDmgType, sType);
					end
				end

				if not bCritEffect or rRoll.bCritical then
					rRoll.bEffects = true;

					local rClause = {};
					rClause.dice = {};
					for _,vDie in ipairs(v.dice) do
						table.insert(rRoll.tEffectDice, vDie);
						table.insert(rClause.dice, vDie);
						if rClause.reroll then
							table.insert(rClause.reroll, 0);
						end
						if vDie:sub(1,1) == "-" then
							table.insert(rRoll.aDice, "-p" .. vDie:sub(3));
						else
							table.insert(rRoll.aDice, "p" .. vDie:sub(2));
						end
					end

					rRoll.nEffectMod = rRoll.nEffectMod + v.mod;
					rClause.modifier = v.mod;
					rRoll.nMod = rRoll.nMod + v.mod;

					rClause.stat = "";

					if #aEffectDmgType == 0 then
						table.insert(aEffectDmgType, sEffectBaseType);
					end
					for _,vSpecialDmgType in ipairs(aEffectSpecialDmgType) do
						table.insert(aEffectDmgType, vSpecialDmgType);
					end
					rClause.dmgtype = table.concat(aEffectDmgType, ",");

					table.insert(rRoll.clauses, rClause);
				end
			end
		end

		-- if nEffectCount > 0 then
		-- 	rRoll.nMod = rRoll.nMod + nTotalMod;
		-- 	rRoll.nEffectMod = rRoll.nEffectMod + nTotalMod;

		-- 	for _,vDie in ipairs(aDice) do
		-- 		table.insert(rRoll.tEffectDice, vDie);
		-- 	end
		-- 	rRoll.bEffects = true;
		-- end
	end
end

function onTargeting(rSource, aTargeting, rRolls)
	local result = {};
	for _,rRoll in ipairs(rRolls) do
		local sTarget = rRoll.sDesc:match("%[TARGET:([^]]*)%]")
		if sTarget then
			rRoll.sDesc = rRoll.sDesc:gsub("%[TARGET:[^]]*%]", "")
			local newTarget = ActorManager.resolveActor(sTarget);
			if newTarget then
				table.insert(result, { newTarget });
			end
		end
	end

	if #result > 0 then
		return result;
	end

	return aTargeting;
end

-- Fork the data flow here so that updates to the 5e ruleset don't break all damage
-- it only risks breaking this extensions handling of unit damage.
function applyDamage(rSource, rTarget, rRoll)
	local nodeTarget = ActorManager.getCTNode(rTarget);
	local bIsUnit = ActorManagerKw.isUnit(nodeTarget);
	if bIsUnit then
		applyDamageToUnit(rSource, rTarget, rRoll)
	else
		fApplyDamage(rSource, rTarget, rRoll);
	end
end

-- Trimmed down version of the applyDamge function. Got rid of most of the extraneous stuff:
-- like concentration, half damage, avoidance, death saves, recovery, etc.
function applyDamageToUnit(rSource, rTarget, rRoll)
	-- Get health fields
	local nTotalHP, nTempHP, nWounds;
	local sDamage = rRoll.sDesc;
	local nTotal = rRoll.nTotal;

	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget);
	if not nodeTarget then
		return;
	end
	if sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, "hptotal", 0);
		nTempHP = DB.getValue(nodeTarget, "hptemp", 0);
		nWounds = DB.getValue(nodeTarget, "wounds", 0);
	else
		return;
	end

	-- Remember current health status
	local sOriginalStatus = ActorHealthManager.getHealthStatus(rTarget);

	-- Decode damage/heal description
	local rDamageOutput = ActionDamage.decodeDamageText(nTotal, sDamage);
	rDamageOutput.sOriginal = sDamage:lower();
	rDamageOutput.tNotifications = {};

	-- Healing
	if rDamageOutput.sType == "heal" then
		if nWounds <= 0 then
			table.insert(rDamageOutput.tNotifications, "[NOT WOUNDED]");
		else
			-- Calculate heal amounts
			local nHealAmount = rDamageOutput.nVal;

			-- If healing from zero (or negative), then remove Stable effect and reset wounds to match HP
			if (nHealAmount > 0) and (nWounds >= nTotalHP) then
				nWounds = nTotalHP;
			end

			local nWoundHealAmount = math.min(nHealAmount, nWounds);
			nWounds = nWounds - nWoundHealAmount;

			-- Display actual heal amount
			rDamageOutput.nVal = nWoundHealAmount;
			rDamageOutput.sVal = string.format("%01d", nWoundHealAmount);
		end

	-- Temporary hit points
	elseif rDamageOutput.sType == "temphp" then
		nTempHP = math.max(nTempHP, rDamageOutput.nVal);

	-- Damage
	else
		-- Apply any targeted damage effects 
		if rSource and rTarget and rTarget.nOrder then
			ActionDamage.applyTargetedDmgEffectsToDamageOutput(rDamageOutput, rSource, rTarget);
			ActionDamage.applyTargetedDmgTypeEffectsToDamageOutput(rDamageOutput, rSource, rTarget);
		end

		-- Apply damage type adjustments
		local nDamageAdjust, bVulnerable, bResist = ActionDamage.getDamageAdjust(rSource, rTarget, rDamageOutput.nVal, rDamageOutput);
		local nAdjustedDamage = rDamageOutput.nVal + nDamageAdjust;
		if nAdjustedDamage < 0 then
			nAdjustedDamage = 0;
		end
		if bResist then
			if nAdjustedDamage <= 0 then
				table.insert(rDamageOutput.tNotifications, "[RESISTED]");
			else
				table.insert(rDamageOutput.tNotifications, "[PARTIALLY RESISTED]");
			end
		end
		if bVulnerable then
			table.insert(rDamageOutput.tNotifications, "[VULNERABLE]");
		end

		-- Reduce damage by temporary hit points
		if nTempHP > 0 and nAdjustedDamage > 0 then
			if nAdjustedDamage > nTempHP then
				nAdjustedDamage = nAdjustedDamage - nTempHP;
				nTempHP = 0;
				table.insert(rDamageOutput.tNotifications, "[PARTIALLY ABSORBED]");
			else
				nTempHP = nTempHP - nAdjustedDamage;
				nAdjustedDamage = 0;
				table.insert(rDamageOutput.tNotifications, "[ABSORBED]");
			end
		end

		-- Apply remaining damage
		if nAdjustedDamage > 0 then
			-- Remember previous wounds
			local nPrevWounds = nWounds;

			-- Apply wounds
			nWounds = math.max(nWounds + nAdjustedDamage, 0);

			-- Calculate wounds above HP
			local nRemainder = 0;
			if nWounds > nTotalHP then
				nRemainder = nWounds - nTotalHP;
				nWounds = nTotalHP;
			end

			-- Deal with remainder damage
			if nRemainder > 0 then
				table.insert(rDamageOutput.tNotifications, "[DAMAGE EXCEEDS CASUALTIES BY " .. nRemainder.. "]");
			end
		end

		-- Update the damage output variable to reflect adjustments
		rDamageOutput.nVal = nAdjustedDamage;
		rDamageOutput.sVal = string.format("%01d", nAdjustedDamage);
	end

	-- Add unit conditions
	updateStatusConditions(rSource, rTarget, rDamageOutput, nTotalHP, nWounds)
	-- local immuneToDiminished = EffectManager5E.getEffectsByType(rTarget, "IMMUNE", { "diminished" });
	-- local nHalf = nTotalHP/2;
	-- local isDiminished = EffectManager5E.hasEffect(rTarget, "Diminished")
	-- local isBroken = EffectManager5E.hasEffect(rTarget, "Broken")
	-- if nWounds < nHalf then
	--	 if isDiminished then
	--		 EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Diminished");
	--	 end
	--	 if isBroken then
	--		 EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Broken");
	--	 end
	-- elseif nWounds >= nHalf and nWounds < nTotalHP then
	--	 if not isDiminished and #immuneToDiminished == 0 then
	--		 EffectManager.addEffect("", "", ActorManager.getCTNode(rTarget), { sName = "Diminished", nDuration = 0 }, true);

	-- 		-- Only roll morale if this is a damage roll, not heal or temp hp
	-- 		if rDamageOutput.sType == "heal" then
	-- 		elseif rDamageOutput.sType == "temphp" then
	-- 		else
	-- 			ActorManagerKw.rollMoraleTestForDiminished(rTarget, rSource);
	-- 		end
	--	 end
	--	 if isBroken then
	--		 EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Broken");
	--	 end
	-- elseif nWounds >= nTotalHP then
	--	 if isDiminished then
	--		 EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Diminished");
	--	 end
	--	 if not isBroken then
	--		 EffectManager.addEffect("", "", ActorManager.getCTNode(rTarget), { sName = "Broken", nDuration = 0 }, true);
	--	 end
	-- end

	-- Set health fields
	DB.setValue(nodeTarget, "hptemp", "number", nTempHP);
	DB.setValue(nodeTarget, "wounds", "number", nWounds);

	-- Check for status change
	local bShowStatus = false;
	if ActorManager.getFaction(rTarget) == "friend" then
		bShowStatus = not OptionsManager.isOption("SHPC", "off");
	else
		bShowStatus = not OptionsManager.isOption("SHNPC", "off");
	end
	if bShowStatus then
		local sNewStatus = ActorHealthManager.getHealthStatus(rTarget);
		if sOriginalStatus ~= sNewStatus then
			table.insert(rDamageOutput.tNotifications, "[" .. Interface.getString("combat_tag_status") .. ": " .. sNewStatus .. "]");
		end
	end

	-- Output results
	rRoll.sDamageText = rDamageOutput.sTypeOutput;
	rRoll.nTotal = tonumber(rDamageOutput.sVal) or 0;
	rRoll.sResults = table.concat(rDamageOutput.tNotifications, " ");
	ActionDamage.messageDamage(rSource, rTarget, rRoll);

	if nWounds >= nTotalHP then
		--handleEndure(rSource, rTarget, rDamageOutput)
	end
end

function updateStatusConditions(rSource, rTarget, rDamageOutput, nTotalHP, nWounds, bHideOutput)
	local showOutput = true;
	if bHideOutput then
		showOutput = false;
	end
	local immuneToDiminished = EffectManager5E.getEffectsByType(rTarget, "IMMUNE", { "diminished" });
	local nHalf = nTotalHP/2;
	local isDiminished = EffectManager5E.hasEffect(rTarget, "Diminished")
	local isBroken = EffectManager5E.hasEffect(rTarget, "Broken")
	if nWounds < nHalf then
		if isDiminished then
			EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Diminished");
		end
		if isBroken then
			EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Broken");
		end
	elseif nWounds >= nHalf and nWounds < nTotalHP then
		if not isDiminished and #immuneToDiminished == 0 then
			EffectManager.addEffect("", "", ActorManager.getCTNode(rTarget), { sName = "Diminished", nDuration = 0 }, showOutput);

			if rDamageOutput then
				-- Only roll morale if this is a damage roll, not heal or temp hp
				if rDamageOutput.sType == "heal" then
				elseif rDamageOutput.sType == "temphp" then
				else
					ActorManagerKw.rollMoraleTestForDiminished(rTarget, rSource);
				end
			end
		end
		if isBroken then
			EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Broken");
		end
	elseif nWounds >= nTotalHP then
		if isDiminished then
			EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Diminished");
		end
		if not isBroken then
			EffectManager.addEffect("", "", ActorManager.getCTNode(rTarget), { sName = "Broken", nDuration = 0 }, showOutput);
		end
	end
end

-- The extra bits here are only to check if the roll is an attack or power test
-- so that we can check for IMMUNE: attack and IMMUNE: power
-- Since this function only looks for a strict text match for 'attack' and 'power'
function getDamageAdjust(rSource, rTarget, nDamage, rDamageOutput)
	local nDamageAdjust, bVulnerable, bResist = fGetDamageAdjust(rSource, rTarget, nDamage, rDamageOutput);

	-- Only do this extra processing for units
	if ActorManagerKw.isUnit(rTarget) then
		local bIsAttack = rDamageOutput.sOriginal:match("attack") ~= nil;
		local bIsPower = rDamageOutput.sOriginal:match("power") ~= nil;

		local aImmune = EffectManager5E.getEffectsByType(rTarget, "IMMUNE", {"attack", "power"}, rSource);

		local bImmuneToAttack = false;
		local bImmuneToPower = false;
		for _,v in pairs(aImmune) do
			for _,vType in pairs(v.remainder) do
				if vType == "attack" then
					bImmuneToAttack = true;
				elseif vType == "power" then
					bImmuneToPower = true;
				end
			end
		end

		-- Handle immunity
		if (bImmuneToAttack and bIsAttack) or (bImmuneToPower and bIsPower)then
			bResist = true;
			nDamageAdjust = -nDamage;
		end
	end

	-- Results
	return nDamageAdjust, bVulnerable, bResist;
end

-- There's something really bizarre going on here
-- the get effects functions are returning no effects, as far as I can tell
-- they're doing that because isActive is returning 0, even though the DB has it set to 1
function handleEndure(rSource, rTarget, rDamageOutput)
	local effects = EffectManager5E.getEffectsByType(rTarget, "endure", {}, rSource);

	local aMatch = nil;
	for _,v in pairs(effects) do
		local rAction = {};

		rAction.dc = v.modifier or 0;
		for _,vRemainder in pairs(v.remainder) do
			local s = vRemainder:lower();
			if s == "reaction" then
				rAction.bReaction = true;
			elseif StringManager.contains(DataCommon.abilities, s) then
				rAction.stat = s;
			end
		end

		-- Take the action with the lowest dc
		if rAction.dc < aMatch.dc then
			aMatch = rAction;
		end
	end

	if aMatch then
		local bReactionUsed = ActorManagerKw.hasUsedReaction(rTarget)
		-- if unit has already used a reaction, and one is needed for this roll, bail
		if aMatch.bReaction and bReactionUsed then
			return;
		end

		-- Mark reaction as used
		if aMatch.bReaction then
			ActionTest.notifyUseReaction(rTarget);
		end

		ActionEndure.performRoll(nil, rTarget, aMatch);
	end
end