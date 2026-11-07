local ADDON_NAME = ...
local CALLER_ID = ADDON_NAME

-- Name of the Auctionator shopping list this addon owns. It is replaced on every update.
local LIST_NAME = "RestedXP"

-- How many guides after the loaded one count as well.
local NEXT_GUIDES = 1

local isGerman = GetLocale() == "deDE"
local L = {
	UPDATED = isGerman and "Einkaufsliste |cffffd100%s|r aktualisiert: %d Item(s)." or "Shopping list |cffffd100%s|r updated: %d item(s).",
	EMPTY = isGerman and "Der Guide verlangt gerade nichts aus dem Auktionshaus." or "The guide doesn't ask for anything from the auction house right now.",
	SSF = isGerman and "Solo Self Found ist in RestedXP aktiv, die Liste bleibt leer." or "Solo Self Found is enabled in RestedXP, the list stays empty.",
	NO_GUIDE = isGerman and "Kein RestedXP-Guide geladen." or "No RestedXP guide loaded.",
	NO_AUCTIONATOR = isGerman and "Auctionator fehlt oder ist zu alt (keine Einkaufslisten-API)." or "Auctionator is missing or too old (no shopping list API).",
	ITEM_LINE = "  %dx %s",
}

local function Print( fmt, ... )
	print( "|cff33ff99Auctionator RestedXP|r: " .. string.format( fmt, ... ) )
end

local GetItemCount = ( C_Item and C_Item.GetItemCount ) or _G.GetItemCount
local GetItemInfo = ( C_Item and C_Item.GetItemInfo ) or _G.GetItemInfo

local function IsQuestDone( questId )
	questId = tonumber( questId )
	if not questId or questId <= 0 then return false end
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return C_QuestLog.IsQuestFlaggedCompleted( questId ) == true
	end
	return false
end

local function HasAuctionatorAPI( )
	return type( Auctionator ) == "table" and type( Auctionator.API ) == "table" and type( Auctionator.API.v1 ) == "table"
		and type( Auctionator.API.v1.CreateShoppingList ) == "function"
		and type( Auctionator.API.v1.ConvertToSearchString ) == "function"
end

local function RXPGuide( )
	local rxp = _G.RXP
	if type( rxp ) ~= "table" or type( rxp.currentGuide ) ~= "table" or type( rxp.currentGuide.steps ) ~= "table" then
		return nil
	end
	return rxp.currentGuide
end

local function IsSoloSelfFound( )
	local rxp = _G.RXP
	return type( rxp ) == "table" and type( rxp.settings ) == "table" and type( rxp.settings.profile ) == "table"
		and rxp.settings.profile.soloSelfFound == true
end

-- The guide named by #next, parsed and filtered for this character like RestedXP does when it loads it.
-- #next may list several guides separated by ";", each optionally prefixed with "<group>\";
-- RestedXP takes the first one that is active for the character, else the last one.
-- RXP.functions.next is not called on purpose: in some cases it loads the guide instead of returning it.
local nextGuideCache = { }
local function NextGuide( guide )
	local rxp = _G.RXP
	if type( guide.next ) ~= "string" or type( rxp.GetGuideTable ) ~= "function" or type( rxp.FetchGuide ) ~= "function" or type( rxp.ProcessGuideTable ) ~= "function" then
		return nil
	end

	local found
	for entry in string.gmatch( guide.next, "[^;]+" ) do
		local group, name = string.match( entry, "^%s*(.-)%s*\\%s*(.-)%s*$" )
		if not group then
			group, name = guide.group, strtrim( entry )
		end
		local ok, candidate = pcall( rxp.GetGuideTable, group, name )
		if ok and type( candidate ) == "table" then
			found = candidate
			local okActive, active = pcall( rxp.IsGuideActive or function( ) return true end, candidate )
			if okActive and active then break end
		end
	end
	if not found then return nil end

	local key = tostring( found.group ) .. "|" .. tostring( found.name )
	if nextGuideCache[key] == nil then
		local ok, processed = pcall( function( )
			local fetched = rxp:FetchGuide( found.group, found.name )
			return fetched and fetched.steps and rxp.ProcessGuideTable( fetched )
		end )
		nextGuideCache[key] = ok and type( processed ) == "table" and type( processed.steps ) == "table" and processed or false
	end
	return nextGuideCache[key] or nil
end

-- Whether RestedXP would show the step for this character (season, phase, Solo Self Found, dungeons, ...).
local function IsShown( step, guide )
	local rxp = _G.RXP
	if type( rxp.IsStepShown ) ~= "function" then return true end
	local ok, shown = pcall( rxp.IsStepShown, step, guide )
	return not ok or shown and true or false
end

-- An auction house purchase is a step tagged #ah that targets an auctioneer. The guides keep the
-- English NPC names in .target even when the guide text is translated, so "Auctioneer" is reliable.
-- #ah alone is not enough: it only means "hidden in Solo Self Found mode" and is also used for
-- looting, vendor and mailbox steps.
local function IsAuctionStep( step )
	if not step.ah or type( step.elements ) ~= "table" then return false end
	for _, element in ipairs( step.elements ) do
		if element.tag == "target" and type( element.targets ) == "table" then
			for _, name in ipairs( element.targets ) do
				if type( name ) == "string" and ( string.find( name, "Auctioneer", 1, true ) or string.find( name, "Auktionator", 1, true ) ) then
					return true
				end
			end
		end
	end
	return false
end

-- Adds the items of an auction house step to needed = { [itemID] = quantity }.
-- The same item often appears in several steps (purchase and turn-in), so the largest quantity wins.
local function ReadStep( needed, step )
	for _, element in ipairs( step.elements ) do
		if element.tag == "collect" and tonumber( element.id ) then
			local id = tonumber( element.id )
			local qty = tonumber( element.qty ) or 1
			-- RestedXP keeps the remaining amount up to date for the active step (quest objectives already done)
			if step.active and tonumber( element.numRequired ) then
				qty = tonumber( element.numRequired )
			end
			-- by default a collect element is done once its quest is turned in
			local done = element.questId and not element.ignoreTurnIn and IsQuestDone( element.questId )
			if not done and qty > 0 and qty > ( needed[id] or 0 ) then
				needed[id] = qty
			end
		end
	end
end

-- { [itemID] = quantity still to buy }, after subtracting what is in the bags and the bank
local function Collect( )
	local needed = { }
	local guide = RXPGuide( )
	if not guide then return needed end

	local current = tonumber( RXPCData and RXPCData.currentStep ) or 1
	local skipped = RXPCData and RXPCData.stepSkip or { }

	-- the current and all following steps, plus earlier steps that are still active (sticky)
	for index, step in ipairs( guide.steps ) do
		if ( index >= current or step.active ) and not skipped[index] and IsAuctionStep( step ) and IsShown( step, guide ) then
			ReadStep( needed, step )
		end
	end

	-- every step of the following guides
	local nextGuide = guide
	for _ = 1, NEXT_GUIDES do
		nextGuide = NextGuide( nextGuide )
		if not nextGuide then break end
		for _, step in ipairs( nextGuide.steps ) do
			if IsAuctionStep( step ) and IsShown( step, nextGuide ) then
				ReadStep( needed, step )
			end
		end
	end

	local missing = { }
	for id, qty in pairs( needed ) do
		local have = GetItemCount( id, true ) or 0
		if qty > have then
			missing[id] = qty - have
		end
	end
	return missing
end

-- Item names are needed for the Auctionator search; load missing ones from the server first.
local function WithItemNames( ids, callback )
	local pending = 0
	local finished = false
	local function Done( )
		if pending == 0 and not finished then
			finished = true
			callback( )
		end
	end
	for _, id in ipairs( ids ) do
		if not GetItemInfo( id ) and Item and Item.CreateFromItemID then
			local item = Item:CreateFromItemID( id )
			if not item:IsItemEmpty( ) then
				pending = pending + 1
				item:ContinueOnItemLoad( function( )
					pending = pending - 1
					Done( )
				end )
			end
		end
	end
	Done( )
end

local lastSignature
local updating = false

-- verbose: also print when nothing changed (manual refresh via slash command)
local function UpdateList( verbose )
	if not HasAuctionatorAPI( ) then
		if verbose then Print( L.NO_AUCTIONATOR ) end
		return
	end
	if not RXPGuide( ) then
		if verbose then Print( L.NO_GUIDE ) end
		return
	end
	if updating then return end

	local missing = IsSoloSelfFound( ) and { } or Collect( )
	local ids = { }
	for id in pairs( missing ) do ids[#ids + 1] = id end
	table.sort( ids )

	local parts = { }
	for _, id in ipairs( ids ) do parts[#parts + 1] = id .. "x" .. missing[id] end
	local signature = table.concat( parts, "," )
	-- recreate the list if it was deleted in Auctionator in the meantime
	local listExists = pcall( Auctionator.API.v1.GetShoppingListItems, CALLER_ID, LIST_NAME )
	if signature == lastSignature and listExists and not verbose then return end
	local hadItems = lastSignature ~= nil and lastSignature ~= ""

	updating = true
	WithItemNames( ids, function( )
		updating = false
		local searchStrings, lines = { }, { }
		for _, id in ipairs( ids ) do
			local name = GetItemInfo( id )
			if name then
				searchStrings[#searchStrings + 1] = Auctionator.API.v1.ConvertToSearchString( CALLER_ID, {
					searchString = name,
					isExact = true,
					quantity = missing[id],
				} )
				local _, link = GetItemInfo( id )
				lines[#lines + 1] = string.format( L.ITEM_LINE, missing[id], link or name )
			end
		end

		local ok, err = pcall( Auctionator.API.v1.CreateShoppingList, CALLER_ID, LIST_NAME, searchStrings )
		if not ok then
			Print( "%s", tostring( err ) )
			return
		end
		lastSignature = signature

		if #searchStrings == 0 then
			-- stay quiet on every auction house visit without purchases
			if verbose or hadItems then
				Print( IsSoloSelfFound( ) and L.SSF or L.EMPTY )
			end
		else
			Print( L.UPDATED, LIST_NAME, #searchStrings )
			for _, line in ipairs( lines ) do print( line ) end
		end
	end )
end

-- Update when the auction house opens, and while it is open whenever the guide or step changes.
local auctionHouseOpen = false
local lastState

local function GuideState( )
	local guide = RXPGuide( )
	return guide and string.format( "%s|%s|%s", tostring( guide.group ), tostring( guide.name ), tostring( RXPCData and RXPCData.currentStep ) ) or ""
end

local frame = CreateFrame( "Frame" )
frame:RegisterEvent( "AUCTION_HOUSE_SHOW" )
frame:RegisterEvent( "AUCTION_HOUSE_CLOSED" )
frame:SetScript( "OnEvent", function( _, event )
	if event == "AUCTION_HOUSE_SHOW" then
		auctionHouseOpen = true
		lastState = GuideState( )
		-- let Auctionator set up its auction house tabs first
		C_Timer.After( 0.5, function( )
			if auctionHouseOpen then UpdateList( false ) end
		end )
	elseif event == "AUCTION_HOUSE_CLOSED" then
		auctionHouseOpen = false
	end
end )

C_Timer.NewTicker( 2, function( )
	if not auctionHouseOpen then return end
	local state = GuideState( )
	if state ~= lastState then
		lastState = state
		UpdateList( false )
	end
end )

SLASH_AUCTIONATORRESTEDXP1 = "/arxp"
SLASH_AUCTIONATORRESTEDXP2 = "/auctionatorrestedxp"
SlashCmdList.AUCTIONATORRESTEDXP = function( )
	UpdateList( true )
end
