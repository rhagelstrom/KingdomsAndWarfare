-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--
OOB_MSGTYPE_NOTIFYDIMINISH = "notifydiminish"

function onInit()
	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_NOTIFYDIMINISH, handleDiminish);
	ActionsManager.registerModHandler("diminished", modDiminished);
	ActionsManager.registerResultHandler("diminished", onDiminished)
end

function performRoll(draginfo, rUnit, rAttacker, rAction)
	local rRoll = getRoll(rUnit, rAttacker, rAction);
	
	ActionsManager.performAction(draginfo, rUnit, rRoll);
end

function getRoll(rUnit, rAttacker, rAction)
	local bADV = rAction.bADV or false;
	local bDIS = rAction.bDIS or false;
	
	-- Build basic roll
	local rRoll = {};
	rRoll.sType = "diminished";
	rRoll.aDice = { "d20" };
	rRoll.nMod = rAction.modifier or 0;
	
	-- Build the description label
	rRoll.sDesc = "[TEST] Morale (Diminished";
	if rAttacker and rAttacker.sName then
		rRoll.sDesc = rRoll.sDesc .. " by " .. rAttacker.sName;
	end
	rRoll.sDesc = rRoll.sDesc .. ")"
	
	-- Add crit range
	if rAction.nCritRange then
		rRoll.sDesc = rRoll.sDesc .. " [CRIT " .. rAction.nCritRange .. "]";
	end

	if rAttacker and rAttacker.sCreatureNode then
		rRoll.sDesc = rRoll.sDesc .. "[ATTACKER:" .. rAttacker.sCreatureNode .. "]"
	end

	-- Add advantage/disadvantage tags
	if bADV then
		rRoll.sDesc = rRoll.sDesc .. " [ADV]";
	end
	if bDIS then
		rRoll.sDesc = rRoll.sDesc .. " [DIS]";
	end

	rRoll.nTarget = rAction.nTarget or 13;

	return rRoll;
end

function modDiminished(rSource, rTarget, rRoll)
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

	local sAttacker = rRoll.sDesc:match("%[ATTACKER:(.-)%]")
	if sAttacker then
		rRoll.sDesc = rRoll.sDesc:gsub("%[ATTACKER:.-%]", "");
		local rAttacker = ActorManager.resolveActor(sAttacker);
		if EffectManager5E.hasEffect(rAttacker, "GRANTADVDIM", rSource) then
			bADV = true;
			bEffects = true;			
		elseif EffectManager5E.hasEffect(rAttacker, "GRANTDISDIM", rSource) then
			bDIS = true;
			bEffects = true;			
		end
	end

	local aTestFilter = { "morale", "diminished" };
	if rSource then
		-- Get attack effect modifiers
		local bEffects = false;
		local nEffectCount;
		aAddDice, nAddMod, nEffectCount = EffectManager5E.getEffectsBonus(rSource, sModStat, false, {}, rTarget);
		if (nEffectCount > 0) then
			bEffects = true;
		end

		if EffectManager5E.hasEffect(rSource, "ADVTEST", rTarget) then
			bADV = true;
			bEffects = true;
		elseif #(EffectManager5E.getEffectsByType(rSource, "ADVTEST", aTestFilter, rTarget)) > 0 then
			bADV = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffect(rSource, "DISTEST", rTarget) then
			bDIS = true;
			bEffects = true;
		elseif #(EffectManager5E.getEffectsByType(rSource, "DISTEST", aTestFilter, rTarget)) > 0 then
			bDIS = true;
			bEffects = true;
		end

		-- Handle automatic success
		if EffectManager5E.hasEffect(rSource, "AUTOPASS", rTarget) then
			table.insert(aAddDesc, "[AUTOPASS]");
		elseif #EffectManager5E.getEffectsByType(rSource, "AUTOPASS", aTestFilter, rTarget) > 0 then
			table.insert(aAddDesc, "[AUTOPASS]");
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

function onDiminished(rSource, rTarget, rRoll)
	ActionsManager2.decodeAdvantage(rRoll);

	local sModStat = "morale";
	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);
	rMessage.text = string.gsub(rMessage.text, " %[AUTOPASS%]", "");

	local rAction = {};
	rAction.nTotal = ActionsManager.total(rRoll);
	rAction.aMessages = {};

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

	Comm.deliverChatMessage(rMessage);
	notifyDiminished(rSource, rTarget, false, rRoll.sDesc, rAction.nTotal, rRoll.nTarget, table.concat(rAction.aMessages, " "))	;

	if rAction.sResult == "miss" or rAction.sResult == "fumble" then
		local rDmgRoll = {}
		rDmgRoll.sLabel = "Diminished";
		rDmgRoll.bSecret = false;
		rDmgRoll.nTotal = 1;
		rDmgRoll.sDesc = rRoll.sDesc;
		ActionDamage.notifyApplyDamage(rSource, rSource, rDmgRoll);
	end
end

function notifyDiminished(rSource, rTarget, bSecret, sDesc, nTotal, nDC, sResults)
	local msgOOB = {};
	msgOOB.type = OOB_MSGTYPE_NOTIFYDIMINISH;
	
	if bSecret then
		msgOOB.nSecret = 1;
	else
		msgOOB.nSecret = 0;
	end
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

function handleDiminish(msgOOB)
	local rSource = ActorManager.resolveActor(msgOOB.sSourceNode);
	local rTarget = ActorManager.resolveActor(msgOOB.sTargetNode);
	local bSecret = msgOOB.nSecret == "1";

	local msgShort = {font = "msgfont"};
	local msgLong = {font = "msgfont"};
	msgShort.text = "Diminish"
	msgLong.text = "Diminish" .. " [" .. msgOOB.nTotal .. "]";

	if (tonumber(msgOOB.nDC) or 0) > 0 then
		msgLong.text = msgLong.text .. "[vs. DC " .. msgOOB.nDC .. "]";
	end
	msgShort.text = msgShort.text .. " ->";
	msgLong.text = msgLong.text .. " ->";
	if rSource then
		msgShort.text = msgShort.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]";
		msgLong.text = msgLong.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]";
	end
	if sResults ~= "" then
		msgLong.text = msgLong.text .. " " .. msgOOB.sResults;
	end	

	ActionsManager.outputResult(bSecret, rSource, rTarget, msgLong, msgShort);
end