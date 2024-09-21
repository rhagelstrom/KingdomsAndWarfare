-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

function onInit()
	if super and super.onInit then
		super.onInit();
	end
	
	if isReadOnly() then
		self.update(true);
	else
		local node = getDatabaseNode();
		if not node or node.isReadOnly() then
			self.update(true);
		end
	end
end

function update(bReadOnly, bForceHide)
	-- CoreRPG was updated so that whne cyclers change value, it calls self.update through a DB handler
	-- However we use update() to manage readonly/visibility, like every other window control
	-- So we need to process vis/readonly updates when bReadOnly isn't a databasenode
	-- But still need to call super.update() when it is, since stringcycler now also uses update()
	-- bReadOnly is a DB Node because of the line DB.addHandler(_sSource, "onUpdate", self.update);
	if type(bReadOnly) ~= "databasenode" then
		local bLocalShow;
		if bForceHide then
			bLocalShow = false;
		else
			bLocalShow = true;
		end
		
		setReadOnly(bReadOnly);
		setVisible(bLocalShow);
		
		local sLabel = getName() .. "_label";
		if window[sLabel] then
			window[sLabel].setVisible(bLocalShow);
		end
		if separator then
			if window[separator[1]] then
				window[separator[1]].setVisible(bLocalShow);
			end
		end
	end

	if super.update then
		super.update();
	end
	
	return bLocalShow;
end
