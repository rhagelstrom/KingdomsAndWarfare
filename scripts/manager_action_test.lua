-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

OOB_MSGTYPE_APPLYTEST = "applytest";
OOB_MSGTYPE_USEREACTION = "usereaction";

function onInit()
	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_APPLYTEST, handleApplyTest);
	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_USEREACTION, handleUseReaction);

	ActionsManager.registerTargetingHandler("test", onTargeting);
	ActionsManager.registerModHandler("test", modTest);
	ActionsManager.registerResultHandler("test", onTest)
end

function performRoll(draginfo, rUnit, rAction)
	local rRoll = getRoll(rUnit, rAction);
	
	ActionsManager.performAction(draginfo, rUnit, rRoll);
end

function getRoll(rUnit, rAction)
	local bADV = rAction.bADV or false;
	local bDIS = rAction.bDIS or false;
	
	-- Build basic roll
	local rRoll = {};
	rRoll.sType = "test";
	rRoll.aDice = { "d20" };
	if rAction.modifier then
		rRoll.nMod = rAction.modifier;
	else
		rRoll.nMod = ActorManagerKw.getAbilityBonus(rUnit, rAction.stat) or 0;
	end
	
	-- Build the description label
	rRoll.sDesc = "[TEST";
	if rAction.order and rAction.order > 1 then
		rRoll.sDesc = rRoll.sDesc .. " #" .. rAction.order;
	end
	if rAction.range then
		rRoll.sDesc = rRoll.sDesc .. " (" .. rAction.range .. ")";
	end
	rRoll.sDesc = rRoll.sDesc .. "] " .. rAction.label;
	
	-- Add stat bonus
	if rAction.stat then
		local sAbilityEffect = DataCommon.ability_ltos[rAction.stat];
		if sAbilityEffect then
			rRoll.sDesc = rRoll.sDesc .. " [MOD:" .. sAbilityEffect .. "]";
		end
	end

	if rAction.battlemagic then
		rRoll.sDesc = rRoll.sDesc .. " [BATTLE MAGIC]"
	end

	-- Add defense stat
	if rAction.defense then
		rRoll.sDesc = rRoll.sDesc .. " [DEF:" .. rAction.defense .. "]";
	end
	
	-- Add advantage/disadvantage tags
	if bADV then
		rRoll.sDesc = rRoll.sDesc .. " [ADV]";
	end
	if bDIS then
		rRoll.sDesc = rRoll.sDesc .. " [DIS]";
	end

	-- Track if this effect came from this unit, or a different unit
	if rAction.sOrigin then
		rRoll.sDesc = rRoll.sDesc .. " [ORIGIN:" .. rAction.sOrigin .. "]";
	end

	-- It's dumb that I have to do this, but somewhere in the bowels of the roll resolution
	-- workflow units on a PCs' cohorts tab (from friend zone) have the sCTNode value stripped away.
	-- Posibly because the system thinks they're pcs, and treats them differently.
	-- So I have to put the CTNode value in the string so it can be persisted reliably
	if rUnit.sCTNode then
		rRoll.sDesc = rRoll.sDesc .. " [CTNODE:" .. rUnit.sCTNode .. "]";
	end

	rRoll.nTarget = rAction.nTargetDC;

	return rRoll;
end

function onTargeting(rSource, aTargeting, rRolls)
	if rSource and (rSource.sCTNode or "") == "" then
		for k,rRoll in pairs(rRolls) do
			local ctnode = rRoll.sDesc:match("%[CTNODE:([%w%p]+)%]");
			if ctnode then
				rSource.sCTNode = ctnode;
				break;
			end
		end
	end
	local aNewTargets = {};

	if aTargeting and #aTargeting > 0 then
		for _,target in pairs(aTargeting) do
			if target and target[1] and target[1].sType == "unit" then
				table.insert(aNewTargets, target);
			end
		end
	end

	if handleHarrowing(rSource, aTargeting, rRolls) then
		rRolls[1].sDesc = rRolls[1].sDesc .. "[BAIL]";
		rSource = nil;
	end


	return aNewTargets;
end

function handleHarrowing(rSource, aTargets, rRolls)
	-- Check for attack roll
	local bAttack = false;
	for k,v in pairs(rRolls) do
		if v.sDesc:match("Attack") then
			bAttack = true;
		end
	end
	if not bAttack then
		return false;
	end

	-- Check to see if rSource even exists. If it doesn't, don't do anything
	if not rSource then 
		return false;
	end

	-- Handle Harrowing
	local aHarrowUnit = nil;
	if aTargets and #aTargets > 0 then
		for k,target in pairs(aTargets) do
			local isHarrowing = ActorManagerKw.hasHarrowingTrait(target[1])
			if isHarrowing then
				aHarrowUnit = target[1];
			end
		end
	end

	local bResult = false;
	if aHarrowUnit then
		-- Check if source is immune to harrow
		if not EffectManager5E.hasEffectCondition(rSource, "Fearless") then
			local sourceType = ActorManagerKw.getUnitType(rSource.sCreatureNode);
			if sourceType or "" ~= "" then
				local sTypeLower = sourceType:lower();
				if sTypeLower ~= "" then
					if sTypeLower == "infantry" or sTypeLower == "cavalry" or sTypeLower == "aerial" then
						ActionHarrowing.applyAttackState(rSource, aTargets, rRolls);
						ActionHarrowing.performRoll(nil, rSource, aHarrowUnit, {})
						bResult = true;
					end
				end
			end
		end
	end
	return bResult;
end

function modTest(rSource, rTarget, rRoll)
	local aAddDesc = {};
	local aAddDice = {};
	local nAddMod = 0;

	local bADV = false;
	local bDIS = false;
	if rRoll.sDesc:match(" %[ADV%]") then
		bADV = true;
		rRoll.sDesc = rRoll.sDesc:gsub(" %[ADV%]", "");		
	end
	if rRoll.sDesc:match(" %[DIS%]") then
		bDIS = true;
		rRoll.sDesc = rRoll.sDesc:gsub(" %[DIS%]", "");
	end

	local sModStat = rRoll.sDesc:match("%[MOD:(%w+)%]");
	local sStatShort = sModStat;
	if sModStat then
		sModStat = DataCommon.ability_stol[sModStat];
	end

	local aTestFilter = { };
	if sModStat then
		table.insert(aTestFilter, sModStat:lower());
	end
	-- Handle battle magic
	if rRoll.sDesc:match("%[BATTLE MAGIC%]") then
		table.insert(aTestFilter, "battle magic");
	end

	if rSource then
		-- Get attack effect modifiers
		local bEffects = false;
		local nEffectCount;
		aAddDice, nAddMod, nEffectCount = EffectManager5E.getEffectsBonus(rSource, sStatShort, false, {}, rTarget);
		if (nEffectCount > 0) then
			bEffects = true;
		end

		if EffectManager5E.hasEffect(rSource, "ADVTEST", rTarget, false, false) then
			bADV = true;
			bEffects = true;
		elseif #(EffectManager5E.getEffectsByType(rSource, "ADVTEST", aTestFilter, rTarget)) > 0 then
			bADV = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffect(rSource, "DISTEST", rTarget, false, false) then
			bDIS = true;
			bEffects = true;
		elseif #(EffectManager5E.getEffectsByType(rSource, "DISTEST", aTestFilter, rTarget)) > 0 then
			bDIS = true;
			bEffects = true;
		end

		-- Handle automatic success
		if EffectManager5E.hasEffect(rSource, "AUTOPASS", rTarget, false, false) then
			table.insert(aAddDesc, "[AUTOPASS]");
		elseif #EffectManager5E.getEffectsByType(rSource, "AUTOPASS", aTestFilter, rTarget) > 0 then
			table.insert(aAddDesc, "[AUTOPASS]");
		end

		-- Handle all of the conditions here
		if sModStat == "attack" and EffectManager5E.hasEffect(rTarget, "Hidden", rSource) then
			bEffects = true;
			bDIS = true;
		end
		if sModStat == "power" and EffectManager5E.hasEffect(rSource, "Weakened", rSource) then
			bEffects = true;
			bDIS = true;
		end

		-- Handle faction-wide morale bonus
		sFaction = ActorManager.getFaction(rSource);
		if sModStat == "morale" then
			local nMoraleBonus = WarfareManager.getFactionMoraleBonus(sFaction);
			if nMoraleBonus > 0 then
				bEffects = true;
				nAddMod = nAddMod + nMoraleBonus;
			end
		end

		-- If effects, then add them
		if bEffects then
			local sEffects = "";
			local sMod = StringManager.convertDiceToString(aAddDice, nAddMod, true);
			if sMod ~= "" then
				sEffects = "[" .. Interface.getString("effects_tag") .. " " .. sMod .. "]";
			else
				sEffects = "[" .. Interface.getString("effects_tag") .. "]";
			end
			table.insert(aAddDesc, sEffects);
		end

		local nFortBonus = 0;
		if sModStat == "power" then
			local _, nPowerFort = WarfareManager.getFortificationBonus(rSource);
			nFortBonus = nPowerFort;
		end

		if nFortBonus > 0 then
			local sAdd = "";
			local sFort = StringManager.convertDiceToString({}, nFortBonus, true);
			if sFort ~= "" then
				sAdd = "[" .. Interface.getString("fortification_tag") .. " " .. sFort .. "]";
			else
				sAdd = "[" .. Interface.getString("fortification_tag") .. "]";
			end
			table.insert(aAddDesc, sAdd);
			nAddMod = nAddMod + nFortBonus;
		end
	end

	-- Advantage and disadvantage from effects on target
	if rTarget and ActorManager.hasCT(rTarget) then
		if sModStat == "attack" then
			if EffectManager5E.hasEffect(rTarget, "GRANTADVATK", rSource) then
				bADV = true;
			end
			if EffectManager5E.hasEffect(rTarget, "GRANTDISATK", rSource) then
				bDIS = true;
			end
		end
		if sModStat == "power" then
			if EffectManager5E.hasEffect(rTarget, "GRANTADVPOW", rSource) then
				bADV = true;
			end
			if EffectManager5E.hasEffect(rTarget, "GRANTDISPOW", rSource) then
				bDIS = true;
			end
		end
	end

	if #aAddDesc > 0 then
		rRoll.sDesc = rRoll.sDesc .. " " .. table.concat(aAddDesc, " ");
	end
	ActionsManager2.encodeDesktopMods(rRoll);
	for _,vDie in ipairs(aAddDice) do
		if vDie:sub(1,1) == "-" then
			table.insert(rRoll.aDice, "-p" .. vDie:sub(3));
		else
			table.insert(rRoll.aDice, "p" .. vDie:sub(2));
		end
	end
	rRoll.nMod = rRoll.nMod + nAddMod;
	
	ActionsManager2.encodeAdvantage(rRoll, bADV, bDIS);
end

function onTest(rSource, rTarget, rRoll)
	ActionsManager2.decodeAdvantage(rRoll);

	local sModStat = rRoll.sDesc:match("%[MOD:(%w+)%]");
	-- if there's still no mod stat, then do more work to find it
	-- This is primarly for drag/drop scenarios
	if not sModStat then
		if rRoll.sDesc:match("Attack") then
			sModStat = "ATK";
		elseif rRoll.sDesc:match("Power") then
			sModStat = "POW"
		elseif rRoll.sDesc:match("Morale") then
			sModStat = "MOR"
		elseif rRoll.sDesc:match("Command") then
			sModStat = "COM"
		end
	end
	if sModStat then
		sModStat = DataCommon.ability_stol[sModStat];
	end

	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);
	rMessage.text = string.gsub(rMessage.text, " %[MOD:[^]]*%]", "");
	rMessage.text = string.gsub(rMessage.text, " %[DEF:[^]]*%]", "");
	rMessage.text = string.gsub(rMessage.text, " %[ORIGIN:[^]]*%]", "");
	rMessage.text = string.gsub(rMessage.text, " %[AUTOPASS%]", "");
	rMessage.text = string.gsub(rMessage.text, " %[BATTLE MAGIC%]", "");
	rMessage.text = string.gsub(rMessage.text, " %[CTNODE:([%w%p]+)%]", "");

	local rAction = {};
	rAction.nTotal = ActionsManager.total(rRoll);
	rAction.aMessages = {};

	-- Handle fortification defense bonus
	local sDef = rRoll.sDesc:match("%[DEF:(%w+)%]");
	-- if Def tag is missing, then base this on the mod stat
	if not sDef then
		if sModStat == "attack" then
			sDef = "defense"
		elseif sModStat == "power" then
			sDef = "toughness"
		end
	end

	local nDefenseVal, nAtkEffectsBonus, nDefEffectsBonus = ActorManagerKw.getDefenseValue(rSource, rTarget, rRoll, sDef);
	if nAtkEffectsBonus ~= 0 then
		rAction.nTotal = rAction.nTotal + nAtkEffectsBonus;
		local sFormat = "[" .. Interface.getString("effects_tag") .. " %+d]"
		table.insert(rAction.aMessages, string.format(sFormat, nAtkEffectsBonus));
	end
	if nDefEffectsBonus ~= 0 then
		nDefenseVal = nDefenseVal + nDefEffectsBonus;
		local sFormat = "[" .. Interface.getString("effects_def_tag") .. " %+d]"
		table.insert(rAction.aMessages, string.format(sFormat, nDefEffectsBonus));
	end

	local _, _, nFortBonus = WarfareManager.getFortificationBonus(rTarget);

	if sDef == "defense" and nFortBonus > 0 then
		local sAdd = "";
		local sFort = StringManager.convertDiceToString({}, nFortBonus, true);
		if sFort ~= "" then
			sAdd = "[" .. Interface.getString("fortification_tag") .. " " .. sFort .. "]";
		else
			sAdd = "[" .. Interface.getString("fortification_tag") .. "]";
		end
		table.insert(rAction.aMessages, sAdd);
		nDefenseVal = nDefenseVal + nFortBonus;
	end

	if not nDefenseVal and rRoll.nTarget then
		nDefenseVal = tonumber(rRoll.nTarget)
	end

	local sCritThreshold = string.match(rRoll.sDesc, "%[CRIT (%d+)%]");
	local nCritThreshold = tonumber(sCritThreshold) or 20;
	if nCritThreshold < 2 or nCritThreshold > 20 then
		nCritThreshold = 20;
	end

	-- Handle automatic success
	local sAutoPass = string.match(rRoll.sDesc, "%[AUTOPASS%]");

	rAction.nFirstDie = 0;
	if #(rRoll.aDice) > 0 then
		rAction.nFirstDie = rRoll.aDice[1].result or 0;
	end

	-- rTarget should only be set if we're rolling attack or power. 
	if rTarget and (sModStat == "attack" or sModStat == "power") then
		if sAutoPass then
			rAction.sResult = "hit";
			table.insert(rAction.aMessages, "[AUTOMATIC HIT]")
		elseif rAction.nFirstDie >= nCritThreshold then
			rAction.bSpecial = true;
			rAction.sResult = "crit";
			table.insert(rAction.aMessages, "[CRITICAL HIT]");
		elseif rAction.nFirstDie == 1 then
			rAction.sResult = "fumble";
			table.insert(rAction.aMessages, "[AUTOMATIC MISS]");
		elseif nDefenseVal then
			if rAction.nTotal >= nDefenseVal then
				rAction.sResult = "hit";
				table.insert(rAction.aMessages, "[HIT]");
			else
				rAction.sResult = "miss";
				table.insert(rAction.aMessages, "[MISS]");
			end
		end
	else
		if sAutoPass then
			rAction.sResult = "hit";
			table.insert(rAction.aMessages, "[AUTOMATIC SUCCESS]")
		elseif rAction.nFirstDie >= nCritThreshold then
			rAction.bSpecial = true;
			rAction.sResult = "crit";
			table.insert(rAction.aMessages, "[CRITICAL SUCCESS]");
		elseif rAction.nFirstDie == 1 then
			rAction.sResult = "fumble";
			table.insert(rAction.aMessages, "[AUTOMATIC FAILURE]");
		elseif rRoll.nTarget then
			if rAction.nTotal >= tonumber(rRoll.nTarget) then
				rAction.sResult = "hit";
				table.insert(rAction.aMessages, "[SUCCESS]");
			else
				rAction.sResult = "miss";
				table.insert(rAction.aMessages, "[FAILURE]");
			end
		end
	end

	-- If a unit makes a test outside of their turn, mark their reaction as used
	if not rRoll.sDesc:match("%[ORIGIN") then
		notifyUseReaction(rSource)
	end

	Comm.deliverChatMessage(rMessage);

	-- rTarget is always an enemy, never the unit itself, so this case, we want to attempt to print out the notification and apply damage
	if rTarget then
		notifyApplyTest(rSource, rTarget, false, sModStat, rRoll.sDesc, rAction.nTotal, nDefenseVal, table.concat(rAction.aMessages, " "));

		-- Handle damage
		if rAction.sResult == "crit" or rAction.sResult == "hit" then
			if sModStat == "attack" or sModStat ==  "power" then
				local nDmg = 1;
				if sModStat == "power" then
					nDmg = ActorManagerKw.getDamage(rSource);
				end

				handleDamage(rSource, rTarget, false, sModStat, nDmg);
			end
		end
	else
		-- In this case, the unit is either rolling a flat check (don't notify) 
		-- or rolling a check with a DC from a unitsavedc roll (notify)
		if rRoll.nTarget then
			notifyApplyTest(rSource, rTarget, false, sModStat, rRoll.sDesc, rAction.nTotal, tonumber(rRoll.nTarget), table.concat(rAction.aMessages, " "));
		end

		-- if this is an attack test with no target, then simply print out a damage roll.
		if sModStat == "attack" then
			handleDamage(rSource, nil, false, sModStat, 1);
		end
	end
end

function handleDamage(rSource, rTarget, bSecret, sModStat, nDamage)
	local rAction = {}
	rAction.label = StringManager.capitalize(sModStat or "");
	rAction.target = ActorManager.getCreatureNodeName(rTarget);
	rAction.clauses = {}

	local clause = {};
	clause.dice = { };
	clause.modifier = nDamage;
	clause.dmgtype = (ActorManagerKw.getUnitType(rSource) or ""):lower();

	table.insert(rAction.clauses, clause);
	
	ActionDamage.performRoll(nil, rSource, rAction)
end

function notifyApplyTest(rSource, rTarget, bSecret, sAttackType, sDesc, nTotal, nDC, sResults)
	local msgOOB = {};
	msgOOB.type = OOB_MSGTYPE_APPLYTEST;
	
	if bSecret then
		msgOOB.nSecret = 1;
	else
		msgOOB.nSecret = 0;
	end
	msgOOB.sAttackType = sAttackType;
	msgOOB.nTotal = nTotal;
	msgOOB.sDesc = sDesc;
	msgOOB.sResults = sResults;
	msgOOB.nDC = nDC or 0;

	msgOOB.sSourceNode = ActorManager.getCreatureNodeName(rSource);
	if rTarget then
		msgOOB.sTargetNode = ActorManager.getCreatureNodeName(rTarget);
	end

	Comm.deliverOOBMessage(msgOOB, "");
end

function handleApplyTest(msgOOB)
	local rSource = ActorManager.resolveActor(msgOOB.sSourceNode);
	local rTarget = ActorManager.resolveActor(msgOOB.sTargetNode);
	
	-- Print message to chat window
	local nTotal = tonumber(msgOOB.nTotal) or 0;
	applyTest(rSource, rTarget, (tonumber(msgOOB.nSecret) == 1), msgOOB.sAttackType, msgOOB.sDesc, nTotal, tonumber(msgOOB.nDC) or 0, msgOOB.sResults);
end

function applyTest(rSource, rTarget, bSecret, sAttackType, sDesc, nTotal, nDC, sResults)
	local msgShort = {font = "msgfont"};
	local msgLong = {font = "msgfont"};
	
	msgShort.text = StringManager.capitalize(sAttackType or "Test");
	msgLong.text = StringManager.capitalize(sAttackType or "Test") .. " [" .. nTotal .. "]";
	if (nDC or 0) > 0 then
		msgLong.text = msgLong.text .. "[vs. ";
		local sDef = sDesc:match("%[DEF:(.-)%]");
		if sDef then
			msgLong.text = msgLong.text .. " " .. StringManager.capitalize(sDef) .. " ";
		else
			msgLong.text = msgLong.text .. " DC ";
		end
		msgLong.text = msgLong.text .. nDC .. "]";
	end
	msgShort.text = msgShort.text .. " ->";
	msgLong.text = msgLong.text .. " ->";
	if rSource then
		msgShort.text = msgShort.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]";
		msgLong.text = msgLong.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]";
	end
	if rTarget then
		msgShort.text = msgShort.text .. " [at " .. ActorManager.getDisplayName(rTarget) .. "]";
		msgLong.text = msgLong.text .. " [at " .. ActorManager.getDisplayName(rTarget) .. "]";
	end
	if sResults ~= "" then
		msgLong.text = msgLong.text .. " " .. sResults;
	end
	
	if string.match(sResults, "%[AUTOMATIC HIT%]") then
		msgLong.icon = "roll_attack_hit";
	elseif string.match(sResults, "%[CRITICAL HIT%]") then
		msgLong.icon = "roll_attack_crit";
	elseif string.match(sResults, "HIT%]") then
		msgLong.icon = "roll_attack_hit";
	elseif string.match(sResults, "MISS%]") then
		msgLong.icon = "roll_attack_miss";
	elseif string.match(sResults, "%[AUTOMATIC MISS%]") then
		msgLong.icon = "roll_attack_miss";
	elseif string.match(sResults, "%[AUTOMATIC SUCCESS%]") then
		--msgLong.icon = "roll_attack_miss";
	elseif string.match(sResults, "%[CRITICAL SUCCESS%]") then
		--msgLong.icon = "roll_attack_miss";
	elseif string.match(sResults, "%[SUCCESS%]") then
		--msgLong.icon = "roll_attack_miss";
	elseif string.match(sResults, "%[FAILURE%]") then
		--msgLong.icon = "roll_attack_miss";
	elseif string.match(sResults, "%[AUTOMATIC FAILURE%]") then
		--msgLong.icon = "roll_attack_miss";
	end
		
	ActionsManager.outputResult(bSecret, rSource, rTarget, msgLong, msgShort);
end

function notifyUseReaction(rSource)
	if not rSource then
		return;
	end

	-- the gm can just set reaction without an OOB. Players need to send the OOB message
	if Session.IsHost then
		useReaction(rSource)
		return;
	end

	local msgOOB = {};
	msgOOB.type = OOB_MSGTYPE_USEREACTION;

	msgOOB.sSourceNode = ActorManager.getCreatureNodeName(rSource);

	Comm.deliverOOBMessage(msgOOB, "");
end

function handleUseReaction(msgOOB)
	local rSource = ActorManager.resolveActor(msgOOB.sSourceNode);
	useReaction(rSource);
end

function useReaction(rSource)
	local bMarkReactions = OptionsManager.getOption("MROT") == "on";
	if rSource and bMarkReactions then
		local sourceNode = ActorManager.getCTNode(rSource)
		local activeNode = CombatManagerKw.getActiveUnitCT();

		if sourceNode ~= activeNode then
			DB.setValue(sourceNode, "reaction", "number", 1);
		end
	end
end
