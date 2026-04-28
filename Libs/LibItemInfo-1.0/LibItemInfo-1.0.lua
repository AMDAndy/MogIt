local MAJOR, MINOR = "LibItemInfo-1.0", 10
local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

-- C_Item.GetItemInfo was removed in WoW 12.0; fall back to global or build a polyfill
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo or function(item)
	local itemID = item
	if type(item) == "string" then
		itemID = strmatch(item, "item:(%d+)")
		if itemID then itemID = tonumber(itemID) end
	end
	if not itemID then return nil end
	local name = C_Item.GetItemNameByID(itemID)
	if not name then return nil end
	local link = C_Item.GetItemLink(itemID) or select(2, C_Item.GetItemInfoInstant(itemID))
	local quality = C_Item.GetItemQualityByID(itemID)
	local icon = C_Item.GetItemIconByID(itemID)
	local _, itemType, itemSubType, equipSlot, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	-- Fields we can't easily get from individual APIs default to nil/0
	local itemLevel = 0
	local requiredLevel = 0
	local maxStack = 1
	local sellPrice = 0
	local bindType = 0
	local expansionID = 0
	local itemSetID = nil
	local isReagent = false
	return name, link, quality, itemLevel, requiredLevel, itemType, itemSubType, maxStack, equipSlot, icon, sellPrice, classID, subClassID, bindType, expansionID, itemSetID, isReagent
end
local type = type
local tonumber = tonumber
local strmatch = strmatch

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

lib.cache = lib.cache or {}
lib.queue = lib.queue or {}

setmetatable(lib, {__index = lib.cache})

local function onUpdate(self)
	for itemID in pairs(lib.queue) do
		if lib.cache[itemID] then
			-- lib.callbacks:Fire("OnItemInfoReceived", itemID)
			lib.queue[itemID] = nil
		end
	end
	lib.callbacks:Fire("OnItemInfoReceivedBatch")
	if not next(lib.queue) then
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
	-- always hide after an update to prevent endless reattempting of items that for whatever reason never returns data
	self:Hide()
end

lib.frame = lib.frame or CreateFrame("Frame")
lib.frame:SetScript("OnEvent", lib.frame.Show)
lib.frame:SetScript("OnUpdate", onUpdate)
lib.frame:Hide()

setmetatable(lib.cache, {
	__index = function(self, item)
		local itemID = item
		if type(item) == "string" then
			itemID = strmatch(item, "item:(%d+)")
			if not itemID then return end
			itemID = tonumber(itemID)
		end
		local name, link, quality, itemLevel, requiredLevel, class, subClass, maxStack, equipSlot, icon, sellPrice, classID, subClassID, bindType, expansionID, itemSetID, isReagent = GetItemInfo(item)
		if not name then
			lib.queue[itemID] = true
			lib.frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
			return
		end
		if type(item) == "string" then
			local baseItem = self[itemID]
			-- apparently cases exist where a query using the item ID won't return any results even though a query with full link did immediately before
			if not baseItem then return end
			-- if the properties are equal to that of the base item, just point this entry at that
			if quality == baseItem.quality and itemLevel == baseItem.itemLevel then
				self[item] = baseItem
				return baseItem
			end
		end
		local itemInfo = {
			name = name,
			quality = quality,
			itemLevel = itemLevel,
			reqLevel = requiredLevel,
			requiredLevel = requiredLevel,
			type = class,
			class = class,
			classID = classID,
			subType = subClass,
			subClass = subClass,
			subClassID = subClassID,
			invType = equipSlot,
			bindType = bindType,
			stackSize = maxStack,
			expansionID = expansionID,
		}
		self[item] = itemInfo
		return itemInfo
	end,
})
