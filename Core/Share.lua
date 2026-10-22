-------------------------------------------------------------------------------
-- SHPlates: Share (export / import your setup as one string)
--
-- The string is:  "SHP1:" + base64( checksum ":" serialized-settings )
-- broken into short lines so the 1.12 edit box wraps it.
--
-- Imports are read by a small parser that only understands tables, text,
-- numbers and true/false. Nothing in a pasted string is ever run as code,
-- so a string from someone else can't do anything but change settings.
-- Every value is checked against the defaults before it is used.
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local copytable = SHPlatesUtility.copyTable
local applysaved = SHPlatesUtility.applySaved

local Share = {}
SHPlates.Share = Share

local PREFIX = "SHP1:"
local LINE = 64

-------------------------------------------------------------------------------
-- Serializer
--   table  { key value key value ... }
--   string s<length>:<bytes>
--   number n<digits>;
--   true t / false f
-------------------------------------------------------------------------------
local function Serialize(value, out, depth)
	depth = depth or 0
	if depth > 20 then return end
	local kind = type(value)
	if kind == "table" then
		table.insert(out, "{")
		for k, v in pairs(value) do
			local kk, vk = type(k), type(v)
			local skip = (kk == "string" and string.sub(k, 1, 1) == "_")
			if (kk == "string" or kk == "number") and not skip and
				(vk == "table" or vk == "string" or vk == "number" or vk == "boolean") then
				Serialize(k, out, depth + 1)
				Serialize(v, out, depth + 1)
			end
		end
		table.insert(out, "}")
	elseif kind == "string" then
		table.insert(out, "s" .. string.len(value) .. ":" .. value)
	elseif kind == "number" then
		table.insert(out, "n" .. tostring(value) .. ";")
	elseif kind == "boolean" then
		table.insert(out, value and "t" or "f")
	end
end

-- Returns value, nextPos  (or nil, errorText)
local function Parse(text, pos, depth)
	if depth > 20 then return nil, "too deeply nested" end
	local tag = string.sub(text, pos, pos)
	if tag == "{" then
		local t = {}
		pos = pos + 1
		while true do
			if pos > string.len(text) then return nil, "cut off" end
			if string.sub(text, pos, pos) == "}" then return t, pos + 1 end
			local k, v, err
			k, pos = Parse(text, pos, depth + 1)
			if k == nil then return nil, pos end
			if type(k) ~= "string" and type(k) ~= "number" then return nil, "bad key" end
			v, pos = Parse(text, pos, depth + 1)
			if v == nil then return nil, pos end
			t[k] = v
		end
	elseif tag == "s" then
		local _, colon, len = string.find(text, "^(%d+):", pos + 1)
		if not colon then return nil, "bad text" end
		len = tonumber(len)
		local value = string.sub(text, colon + 1, colon + len)
		if string.len(value) ~= len then return nil, "cut off" end
		return value, colon + 1 + len
	elseif tag == "n" then
		local _, semi, digits = string.find(text, "^([^;]+);", pos + 1)
		local num = digits and tonumber(digits)
		if not num then return nil, "bad number" end
		return num, semi + 1
	elseif tag == "t" then return true, pos + 1
	elseif tag == "f" then return false, pos + 1
	end
	return nil, "unknown data"
end

-------------------------------------------------------------------------------
-- Base64 (Lua 5.0 has no bit operators, so plain arithmetic)
-------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INDEX = {}
for i = 1, 64 do B64INDEX[string.sub(B64, i, i)] = i - 1 end

local function Encode(data)
	local out = {}
	local len = string.len(data)
	for i = 1, len, 3 do
		local a, b, c = string.byte(data, i), string.byte(data, i + 1), string.byte(data, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144)
		local c2 = math.mod(math.floor(n / 4096), 64)
		local c3 = math.mod(math.floor(n / 64), 64)
		local c4 = math.mod(n, 64)
		table.insert(out, string.sub(B64, c1 + 1, c1 + 1) .. string.sub(B64, c2 + 1, c2 + 1) ..
			(b and string.sub(B64, c3 + 1, c3 + 1) or "=") .. (c and string.sub(B64, c4 + 1, c4 + 1) or "="))
	end
	return table.concat(out)
end

local function Decode(text)
	local out = {}
	local len = string.len(text)
	if math.mod(len, 4) ~= 0 then return nil end
	for i = 1, len, 4 do
		local s1, s2, s3, s4 = string.sub(text, i, i), string.sub(text, i + 1, i + 1),
			string.sub(text, i + 2, i + 2), string.sub(text, i + 3, i + 3)
		local v1, v2 = B64INDEX[s1], B64INDEX[s2]
		local v3 = (s3 == "=") and 0 or B64INDEX[s3]
		local v4 = (s4 == "=") and 0 or B64INDEX[s4]
		if not (v1 and v2 and v3 and v4) then return nil end
		local n = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
		table.insert(out, string.char(math.floor(n / 65536)))
		if s3 ~= "=" then table.insert(out, string.char(math.mod(math.floor(n / 256), 256))) end
		if s4 ~= "=" then table.insert(out, string.char(math.mod(n, 256))) end
	end
	return table.concat(out)
end

local function Checksum(data)
	local sum = 0
	for i = 1, string.len(data) do
		sum = math.mod(sum * 31 + string.byte(data, i), 16777213)
	end
	return sum
end

-------------------------------------------------------------------------------
-- Export
-------------------------------------------------------------------------------
-- What goes in: everything on the options pages. The per-build theme/mode
-- table goes too, plus the build you're on right now, so a character with
-- different talents still gets the same theme and mode.
function Share.Export(includeLearned)
	local DB = SHPlatesDB
	local settings, sig = SHPlates.CurrentSpec()
	local _, class = UnitClass("player")
	local payload = {
		v = 1,
		from = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?"),
		class = class,
		current = { theme = settings.theme or DB.theme, role = settings.role },
		specs = DB.specs,
		themevars = DB.themevars,
		settings = {},
	}
	for key in pairs(SHPlates.DEFAULTS) do
		if key ~= "specs" and key ~= "themevars" and DB[key] ~= nil then
			payload.settings[key] = DB[key]
		end
	end
	if includeLearned and type(SHPlatesLearned) == "table" then
		payload.learned = SHPlatesLearned.nostop
	end
	local out = {}
	Serialize(payload, out)
	local body = table.concat(out)
	local encoded = Encode(Checksum(body) .. ":" .. body)
	local lines = {}
	for i = 1, string.len(encoded), LINE do table.insert(lines, string.sub(encoded, i, i + LINE - 1)) end
	return PREFIX .. "\n" .. table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- Import
-------------------------------------------------------------------------------
-- Returns payload or nil, reason
function Share.Read(text)
	if not text then return nil, "nothing pasted" end
	text = string.gsub(text, "%s", "")
	local start = string.find(text, PREFIX, 1, true)
	if not start then return nil, "that isn't an SHPlates string" end
	text = string.sub(text, start + string.len(PREFIX))
	local raw = Decode(text)
	if not raw then return nil, "the string is damaged or incomplete" end
	local _, colon, sum = string.find(raw, "^(%d+):")
	if not colon then return nil, "the string is damaged" end
	local body = string.sub(raw, colon + 1)
	if tonumber(sum) ~= Checksum(body) then return nil, "the string is incomplete (copy all of it)" end
	local payload, err = Parse(body, 1, 0)
	if type(payload) ~= "table" then return nil, "couldn't read it (" .. tostring(err) .. ")" end
	if payload.v ~= 1 then return nil, "made by a newer SHPlates, update first" end
	return payload
end

local function CopyValue(v) if type(v) == "table" then return copytable(v) end return v end

-- a theme family that is installed here ("Grey", "Neon", "None")
local function ValidTheme(name)
	if type(name) ~= "string" then return false end
	if name == "None" then return true end
	for full in pairs(SHPlatesThemeList) do
		local _, _, family = string.find(full, "^(.-)/")
		if (family or full) == name then return true end
	end
	return false
end

local function Apply(payload)
	local DB = SHPlatesDB
	local D = SHPlates.DEFAULTS
	local count = 0
	-- general settings: only known keys with the right type
	if type(payload.settings) == "table" then
		for key, value in pairs(payload.settings) do
			if D[key] ~= nil and key ~= "specs" and key ~= "themevars" and type(value) == type(D[key])
				and (key ~= "theme" or ValidTheme(value)) then
				DB[key] = CopyValue(value)
				count = count + 1
			end
		end
	end
	-- theme pages: written into the live tables the themes read from
	if type(payload.themevars) == "table" then
		for name, vars in pairs(payload.themevars) do
			if type(name) == "string" and type(vars) == "table" then
				local theme = SHPlatesThemeList[name]
				if type(theme) == "table" and type(theme.vars) == "table" then
					applysaved(theme.vars, vars)
					DB.themevars[name] = theme.vars
				else
					DB.themevars[name] = copytable(vars)  -- theme not installed: keep for later
				end
			end
		end
	end
	-- per-build theme/mode
	local _, myClass = UnitClass("player")
	local sameClass = payload.class == myClass
	local function GoodSpec(s)
		return type(s) == "table" and (s.theme == nil or ValidTheme(s.theme)) and
			(s.role == nil or s.role == "AUTO" or s.role == "Tank" or s.role == "DPS")
	end
	if sameClass and type(payload.specs) == "table" then
		for sig, s in pairs(payload.specs) do
			if type(sig) == "string" and GoodSpec(s) then DB.specs[sig] = { theme = s.theme, role = s.role } end
		end
	end
	local cur = payload.current
	if GoodSpec(cur) and cur.theme then
		-- theme follows to any class; Tank/DPS mode only to the same class
		SHPlates.SetSpecSetting("theme", cur.theme)
		if sameClass and cur.role then SHPlates.SetSpecSetting("role", cur.role) end
	end
	-- learned uninterruptible casts are merged, never removed
	local learned = 0
	if type(payload.learned) == "table" then
		if type(SHPlatesLearned) ~= "table" then SHPlatesLearned = {} end
		if type(SHPlatesLearned.nostop) ~= "table" then SHPlatesLearned.nostop = {} end
		local mine = SHPlatesLearned.nostop
		for mob, spells in pairs(payload.learned) do
			if type(mob) == "string" and type(spells) == "table" then
				mine[mob] = mine[mob] or {}
				for spell, v in pairs(spells) do
					if not mine[mob][spell] then learned = learned + 1 end
					mine[mob][spell] = CopyValue(v)
				end
			end
		end
	end
	-- switch everything over now, no reload needed
	SHPlates:UseAutoHide(DB.autohide)
	SHPlates:SetOverlap(DB.overlap)
	if DB.hidePfUIPlates and SHPlates.Conflicts then SHPlates.Conflicts.KillPfUIPlates() end
	SHPlates.ApplySettings(true)
	if SHPlates.RefreshAllConfigPages then SHPlates.RefreshAllConfigPages() end
	return count, learned, sameClass
end

function Share.Import(text)
	local payload, err = Share.Read(text)
	if not payload then C.print("import failed: " .. err); return false end
	local _, learned, sameClass = Apply(payload)
	local msg = "imported settings from " .. tostring(payload.from)
	if learned > 0 then msg = msg .. ", plus " .. learned .. " learned casts" end
	if not sameClass then msg = msg .. " (different class: theme copied, Tank/DPS mode left as yours)" end
	C.print(msg .. ".")
	return true
end

-------------------------------------------------------------------------------
-- "Share" page in the options window (same idea as pfUI's share window):
-- one text field, Export fills it, paste a string in and press Import.
-------------------------------------------------------------------------------
local function MakeButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetWidth(width or 90); b:SetHeight(22)
	b:SetText(text)
	return b
end

function Share.BuildPage(page)
	local help = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -2)
	help:SetPoint("RIGHT", page, "RIGHT", -2, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Export puts your whole setup in the box: copy it with Ctrl+C. " ..
		"To load a setup, paste a string in the box with Ctrl+V and press Import.")

	local box = CreateFrame("Frame", nil, page)
	box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -32)
	box:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 60)
	box:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	box:SetBackdropColor(0, 0, 0, .8)
	box:SetBackdropBorderColor(.4, .4, .4, 1)

	local scroll = CreateFrame("ScrollFrame", "SHPlatesShareScroll", box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 8)

	local edit = CreateFrame("EditBox", "SHPlatesShareEdit", scroll)
	edit:SetWidth(340); edit:SetHeight(250)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(ChatFontNormal)
	edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	scroll:SetScrollChild(edit)
	box:EnableMouse(true)
	box:SetScript("OnMouseUp", function() edit:SetFocus() end)

	local learned = CreateFrame("CheckButton", "SHPlatesShareLearned", page, "UICheckButtonTemplate")
	learned:SetWidth(24); learned:SetHeight(24)
	learned:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", -2, 30)
	getglobal("SHPlatesShareLearnedText"):SetText("Export learned uninterruptible casts too")

	local status = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 2, 8)
	status:SetWidth(170); status:SetJustifyH("LEFT")

	local importBtn = MakeButton(page, "Import")
	importBtn:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 2)
	local exportBtn = MakeButton(page, "Export")
	exportBtn:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)
	local clearBtn = MakeButton(page, "Clear", 60)
	clearBtn:SetPoint("RIGHT", exportBtn, "LEFT", -8, 0)

	-- Import only lights up for a string that will actually load
	local lastExport
	local function Validate()
		local text = edit:GetText()
		if text == "" then
			importBtn:Disable(); status:SetText(""); return
		end
		local payload, err = Share.Read(text)
		if payload then
			importBtn:Enable()
			if text == lastExport then
				status:SetText("|cff00ff00Your setup, ready to copy|r")
			else
				status:SetText("|cff00ff00Setup from " .. tostring(payload.from) .. "|r")
			end
		else
			importBtn:Disable()
			status:SetText("|cffff6060" .. err .. "|r")
		end
	end

	edit:SetScript("OnTextChanged", function()
		scroll:UpdateScrollChildRect()
		Validate()
	end)

	exportBtn:SetScript("OnClick", function()
		lastExport = Share.Export(learned:GetChecked())
		edit:SetText(lastExport)
		scroll:SetVerticalScroll(0)
		edit:SetFocus()
		edit:HighlightText()
	end)
	importBtn:SetScript("OnClick", function()
		local text = edit:GetText()
		if Share.Import(text) then
			local payload = Share.Read(text)
			status:SetText("|cff00ff00Loaded setup from " .. tostring(payload and payload.from) .. "|r")
		end
	end)
	clearBtn:SetScript("OnClick", function() edit:SetText(""); edit:SetFocus() end)

	page.edit = edit
	page.RefreshAll = Validate
	importBtn:Disable()
end

SHPlatesSlashCommands.export = function() SHPlates.ShowConfigPage("share") end
SHPlatesSlashCommands.import = SHPlatesSlashCommands.export
SHPlatesSlashCommands.share = SHPlatesSlashCommands.export
