-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

function onInit()
	ActionsManager.registerModHandler("domaincheck", modDomainSkillRoll)
	ActionsManager.registerResultHandler("domaincheck", onDomainSkillRoll)
end

function performRoll(draginfo, rActor, rAction)
	local rRoll = getRoll(rActor, rAction);
	
	ActionsManager.performAction(draginfo, rActor, rRoll);
end

function getRoll(rActor, rAction)
	
	-- Build basic roll
	local rRoll = {};
	rRoll.sType = "domaincheck";
	rRoll.aDice = { "d20" };
	rRoll.nMod = rAction.modifier;
	rRoll.sDesc = "[DOMAIN SKILL] " .. StringManager.capitalize(rAction.skill or "");

	return rRoll;
end

function modDomainSkillRoll(rSource, rTarget, rRoll)
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

	if rSource then
		-- Get roll effect modifiers
		local sTest = StringManager.trim(string.match(rRoll.sDesc, "%[DOMAIN SKILL%] ([^[]+)"));
		if sTest then
			local aTestAddDice, nTestAddMod, nTestEffectCount = EffectManager5E.getEffectsBonus(rSource, {"TEST"}, false, {sTest:lower()});
			if nTestEffectCount > 0 then
				bEffects = true;
				for _,v in ipairs(aTestAddDice) do
					table.insert(aAddDice, v);
				end
				nAddMod = nAddMod + nTestAddMod;
			end
		end

		-- Get condition modifiers
		if EffectManager5E.hasEffectCondition(rSource, "ADVTEST") then
			bADV = true;
			bEffects = true;
		elseif #(EffectManager5E.getEffectsByType(rSource, "ADVTEST", aSkillFilter)) > 0 then
			bADV = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffectCondition(rSource, "DISTEST") then
			bDIS = true;
			bEffects = true;
		elseif #(EffectManager5E.getEffectsByType(rSource, "DISTEST", aSkillFilter)) > 0 then
			bDIS = true;
			bEffects = true;
		end

		-- If effects happened, then add note
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

function onDomainSkillRoll(rSource, rTarget, rRoll)
	ActionsManager2.decodeAdvantage(rRoll);
	local nTotal = ActionsManager.total(rRoll);
	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);

	local aNotifications = {}
	local nFirstDie = 0;
	if #(rRoll.aDice) > 0 then
		nFirstDie = rRoll.aDice[1].result or 0;
	end
	if nFirstDie >= 20 then
		table.insert(aNotifications, "[CRITICAL SUCCESS]");
	end
	
	rMessage.text = rMessage.text .. " " .. table.concat(aNotifications, " ");
	Comm.deliverChatMessage(rMessage);
end