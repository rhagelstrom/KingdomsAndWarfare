-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--
local fSetActiveVisible;

function onInit()
    fSetActiveVisible = super.setActiveVisible;
    super.setActiveVisible = setActiveVisible;
    super.onInit();

    -- Watch for the isUnit field, and update graphics accordingly
    local node = getDatabaseNode();
    DB.addHandler(DB.getPath(node, "isUnit"), "onUpdate", onIsUnitUpdate)

    -- Watch for the active field,
    -- Removing for now, until I add a way to check if the current active
    -- CT entry is a unit, in which case don't disable the unit vis toggle
    --DB.addHandler(DB.getPath(node, "active"), "onUpdate", onActiveUpdate)

    setUnitFieldVisibility();
end

function onDrop(x, y, draginfo)
    if Session.IsHost then
        local ctnode = draginfo.getDatabaseNode();
        local bIsCT = (UtilityManager.getRootNodeName(ctnode) == CombatManager.CT_MAIN_PATH);
        if ctnode and ActorManagerKw.isUnit(ctnode) and bIsCT then
            -- only process drops on npcs/pcs, not units
            -- Only process if we're dropping a CT node. If it's not a CT node, then process as normal
            local cmdrnode = getDatabaseNode();
            if not ActorManagerKw.isUnit(cmdrnode) then
                DB.setValue(ctnode, "commander", "string", name.getValue());
                DB.setValue(ctnode, "initresult", "number", initresult.getValue() - 0.1);

                local friendfoe = DB.getValue(cmdrnode, "friendfoe", "")
                if friendfoe ~= "" then
                    DB.setValue(ctnode, "friendfoe", "string", friendfoe)
                end

                -- Setting owner isn't working here
                -- DB.setOwner(ctnode, DB.getOwner(cmdrnode))
                return true;
            end
            return true;
        end
    end
    return false;
end

function onClose()
    local node = getDatabaseNode();
    DB.removeHandler(DB.getPath(node, "isUnit"), "onUpdate", onIsUnitUpdate)
    --DB.removeHandler(DB.getPath(node, "active"), "onUpdate", onActiveUpdate)
end

function onActiveUpdate(nodeUpdated)
    local active = DB.getValue(getDatabaseNode(), "active", 0) == 1;
    if active then
        activateunits.setValue(1);
    else
        activateunits.setValue(0);
    end
end

function onIsUnitUpdate(nodeUpdated)                
    setUnitFieldVisibility();                
end

function setUnitFieldVisibility()
    local v = false;
    if activateactive.getValue() == 1 then
        v = true;
    end
    local sClass, sRecord = link.getValue();
    local bNPC = (sClass ~= "charsheet");
    if bNPC and active.getValue() == 1 then
        v = true;
    end

    local isUnit = ActorManagerKw.isUnit(getDatabaseNode());
    --local isUnit = DB.getValue(getDatabaseNode(), "isUnit", 0) == 1;
    
    activateunits.setEnabled(not isUnit);

    -- reaction.setVisible(v and not isUnit);
    -- reaction_label.setVisible(v and not isUnit);
    actions.setVisible(v and not isUnit);
    actions_label.setVisible(v and not isUnit);
    actions_emptyadd.setVisible(v and not isUnit);
    init.setVisible(v and not isUnit);
    initlabel.setVisible(v and not isUnit);
    ac.setVisible(v and not isUnit);
    aclabel.setVisible(v and not isUnit);
    speed.setVisible(v and not isUnit);
    speedlabel.setVisible(v and not isUnit);

    attack.setVisible(v and isUnit);
    attack_label.setVisible(v and isUnit);
    power.setVisible(v and isUnit);
    power_label.setVisible(v and isUnit);
    morale.setVisible(v and isUnit);
    morale_label.setVisible(v and isUnit);
    command.setVisible(v and isUnit);
    command_label.setVisible(v and isUnit);
    defense.setVisible(v and isUnit);
    defense_label.setVisible(v and isUnit);
    toughness.setVisible(v and isUnit);
    toughness_label.setVisible(v and isUnit);

    rally.setVisible(v and isUnit);
end

function setActiveVisible()
    fSetActiveVisible()
    setUnitFieldVisibility()
end