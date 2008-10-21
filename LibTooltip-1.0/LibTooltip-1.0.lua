assert(LibStub, "LibTooltip-1.0 requires LibStub")
local MAJOR, MINOR = "LibTooltip-1.0", 1
local LibTooltip, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not LibTooltip then return end -- No upgrade needed

-- Internal constants to tweak the layout
local TOOLTIP_PADDING = 10
local CELL_MARGIN = 3

local bgFrame = {
   edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
   bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
   tile = true,
   tileSize = 16,
   edgeSize = 16,
   insets = {left = 5, right = 5, top = 5, bottom = 5}
}

------------------------------------------------------------------------------
-- Tables and locals
------------------------------------------------------------------------------

LibTooltip.frameMeta = LibTooltip.frameMeta or {__index = CreateFrame("Frame")}

LibTooltip.tipProto = LibTooltip.tipProto or setmetatable({}, LibTooltip.frameMeta)
LibTooltip.tipMeta = LibTooltip.tipMeta or {__index = LibTooltip.tipProto}

LibTooltip.providerProto = LibTooltip.providerProto or {}
LibTooltip.providerMeta = LibTooltip.providerMeta or {__index = LibTooltip.providerProto}

LibTooltip.cellProto = LibTooltip.cellProto or setmetatable({}, LibTooltip.frameMeta)
LibTooltip.cellMeta = LibTooltip.cellMeta or { __index = LibTooltip.cellProto }

LibTooltip.activeTooltips = LibTooltip.activeTooltips or {}
LibTooltip.tooltipHeap = LibTooltip.tooltipHeap or {}

LibTooltip.frameHeap = LibTooltip.frameHeap or {}

local tipProto = LibTooltip.tipProto
local tipMeta = LibTooltip.tipMeta

local providerProto = LibTooltip.providerProto
local providerMeta = LibTooltip.providerMeta

local cellProto = LibTooltip.cellProto
local cellMeta = LibTooltip.cellMeta

local activeTooltips = LibTooltip.activeTooltips
local tooltipHeap = LibTooltip.tooltipHeap

local frameHeap = LibTooltip.frameHeap

-- Tooltip private methods
local InitializeTooltip, FinalizeTooltip, ResetTooltipSize

------------------------------------------------------------------------------
-- Public library API
------------------------------------------------------------------------------

function LibTooltip:Acquire(key, ...)
   if key == nil then
      error("LibTooltip:Acquire(): key might not be nil.", 2)
   end
   local tooltip = activeTooltips[key]
   if not tooltip then
      tooltip = tremove(tooltipHeap) or setmetatable(CreateFrame("Frame", nil, UIParent), tipMeta)
      InitializeTooltip(tooltip, key)
      activeTooltips[key] = tooltip
   end
   if select('#', ...) > 0 then
      local ok, msg = pcall(tooltip.SetColumnLayout, tooltip, ...)
      if not ok then error(msg, 2) end -- report error properly
   end
   return tooltip
end

function LibTooltip:IsAcquired(key)
   if key == nil then
      error("LibTooltip:IsAcquired(): key might not be nil.", 2)
   end
   return not not activeTooltips[key]
end

function LibTooltip:Release(tooltip)
   local key = tooltip and tooltip.key
   if not key or activeTooltips[key] ~= tooltip then return end
   tooltip:Hide()
   FinalizeTooltip(tooltip)
   tinsert(tooltipHeap, tooltip)
   activeTooltips[key] = nil
end

function LibTooltip:IterateTooltips()
   return pairs(activeTooltips)
end

------------------------------------------------------------------------------
-- Frame heap
------------------------------------------------------------------------------

local function AcquireFrame(parent)
   local frame = tremove(frameHeap) or CreateFrame("Frame")
   frame:SetParent(parent)
   return frame
end

local function ReleaseFrame(frame)
   frame:Hide()
   frame:SetParent(nil)
   frame:ClearAllPoints()
   tinsert(frameHeap, frame)
end

------------------------------------------------------------------------------
-- CellProvider and Cell
------------------------------------------------------------------------------

-- Provider prototype

function providerProto:AcquireCell(tooltip)
   local cell = tremove(self.heap)
   if not cell then
      cell = setmetatable(CreateFrame("Frame", nil, tooltip), self.cellMetatable)
      cell:InitializeCell()
   else
      cell:SetParent(tooltip)
   end
   cell:SetFrameLevel(tooltip:GetFrameLevel()+1)
   self.cells[cell] = true
   return cell
end

function providerProto:ReleaseCell(cell)
   if not self.cells[cell] then return end
   cell:Hide()
   cell:SetParent(nil)
   cell:ClearAllPoints()
   self.cells[cell] = nil
   tinsert(self.heap, cell)
end

function providerProto:GetCellPrototype()
   return self.cellPrototype, self.cellMetatable
end

function providerProto:IterateCells()
   return pairs(self.cells)
end

-- Cell prototype

function cellProto:GetCellProvider()
   return self.cellProvider
end

function cellProto:ReleaseCell()
   self.cellProvider:ReleaseCell(self)
end

-- Cell provider factory

function LibTooltip:CreateCellProvider(baseProvider)
   local baseMeta, baseProto
   if baseProvider and baseProvider.GetCellPrototype then
      baseProto, baseMeta = baseProvider:GetCellPrototype()
   else
      baseMeta = cellMeta
   end
   local cellProto = setmetatable({}, baseMeta)
   local cellProvider = setmetatable({}, providerMeta)
   cellProvider.heap = {}
   cellProvider.cells = {}
   cellProvider.cellPrototype = cellProto
   cellProvider.cellMetatable = { __index = cellProto }
   cellProto.cellProvider = cellProvider
   return cellProvider, cellProto, baseProto
end

------------------------------------------------------------------------------
-- Basic label provider
------------------------------------------------------------------------------

local labelProvider, labelPrototype = LibTooltip.LabelProvider, LibTooltip.LabelPrototype
if not LibTooltip.LabelProvider then
   labelProvider, labelPrototype = LibTooltip:CreateCellProvider()
   LibTooltip.LabelProvider, LibTooltip.LabelPrototype = labelProvider, labelPrototype
end

function labelPrototype:InitializeCell()
   self.fontString = self:CreateFontString()
   self.fontString:SetAllPoints(self)
end

function labelPrototype:SetupCell(tooltip, value, justification, font, ...)
   local fs = self.fontString
   fs:SetFontObject(font or tooltip:GetFont())
   fs:SetJustifyH(justification)
   fs:SetText(tostring(value))
   fs:Show()
   return fs:GetStringWidth(), fs:GetStringHeight()
end

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

local function checkFont(font, method, level)
   if not font or not font.IsObjectType or not font:IsObjectType("Font") then
      error(method..": font must be Font instance", level+1)
   end
end

local function checkJustification(justification, method, level)
   if justification ~= "LEFT" and justification ~= "CENTER" and justification ~= "RIGHT" then
      error(method..": invalid justification: "..tostring(justification), level+1)
   end
end

------------------------------------------------------------------------------
-- Tooltip prototype
------------------------------------------------------------------------------

function InitializeTooltip(self, key)
   -- (Re)set frame settings
   self:SetBackdrop(bgFrame)
   self:SetBackdropColor(0.09, 0.09, 0.09)
   self:SetBackdropBorderColor(1, 1, 1)
   self:SetAlpha(0.9)
   self:SetScale(1.0)
   self:SetFrameStrata("TOOLTIP")
   
   -- Our data
   self.key = key
   self.numColumns = 0
   self.columns = self.columns or {}
   self.lines = self.lines or {}
   
   self.regularFont = GameTooltipText
   self.headerFont = GameTooltipHeaderText
   
   ResetTooltipSize(self)
end

function tipProto:SetColumnLayout(numColumns, ...)
   if type(numColumns) ~= "number" then
      error("tooltip:SetColumnLayout(): numColumns should be a number, not "..tostring(numColumns), 2)
   elseif numColumns < 1 then
      error("tooltip:SetColumnLayout(): numColumns out of range: "..tostring(numColumns), 2)
   end
   for i = 1, numColumns do
      local justification = select(i, ...) or "LEFT"
      checkJustification(justification, "tooltip:SetColumnLayout("..i..")", 2)
      if self.columns[i] then
         self.columns[i].justification = justification
      else
         self:AddColumn(justification)
      end
   end
end

function tipProto:AddColumn(justification)
   justification = justification or "LEFT"
   checkJustification(justification, "tooltip:AddColumn()", 2)
   local colNum = #self.columns + 1
   local column = AcquireFrame(self)
   column.justification = justification
   column.width = 0
   column:SetWidth(0)
   column:SetPoint("TOP", self, "TOP", 0, -TOOLTIP_PADDING)
   column:SetPoint("BOTTOM", self, "BOTTOM", 0, TOOLTIP_PADDING)
   if colNum > 1 then
      column:SetPoint("LEFT", self.columns[colNum-1], "RIGHT", CELL_MARGIN, 0)
      self.width = self.width + CELL_MARGIN
      self:SetWidth(self.width)
   else
      column:SetPoint("LEFT", self, "LEFT", TOOLTIP_PADDING, 0)
   end
   column:Show()
   self.columns[colNum] = column
   self.numColumns = colNum
end

function FinalizeTooltip(self)
   self:Clear()
   for i, column in ipairs(self.columns) do
      column:Hide()
      ReleaseFrame(column)
      self.columns[i] = nil
   end
end

function ResetTooltipSize(self)
   self.width = 2*TOOLTIP_PADDING
   self.height = 2*TOOLTIP_PADDING
   self:SetWidth(self.width)
   self:SetHeight(self.height)
end

function tipProto:Clear()
   for i, line in ipairs(self.lines) do
      for j, cell in ipairs(line.cells) do
         if cell then
            cell:ReleaseCell()
         end
         line.cells[j] = nil
      end
      line:Hide()
      ReleaseFrame(line)
      self.lines[i] = nil
   end
   for i, column in ipairs(self.columns) do
      column.width = 0
      column:SetWidth(0)
   end
   ResetTooltipSize(self)
end

function tipProto:SetFont(font)
   checkFont(font, "tooltip:SetFont()", 2)
   self.regularFont = font
end

function tipProto:GetFont() return self.regularFont end

function tipProto:SetHeaderFont(font)
   checkFont(font, "tooltip:SetHeaderFont()", 2)
   self.headerFont = font
end

function tipProto:GetHeaderFont() return self.headerFont end

local function SetCell(self, lineNum, colNum, value, font, justification, colSpan, provider, ...)
   -- Line and column checks
   local line = self.lines[lineNum]
   local rightColNum = colNum+colSpan-1
   local leftColumn = self.columns[colNum]
   local rightColumn = self.columns[rightColNum]
   
   -- Release any existing cells, checking for overlaps
   -- We use "false" to indicate unavailable slots
   for i = colNum, rightColNum do
      if line.cells[i] == false then
         error("tooltip:SetCell(): overlapping cells at column "..i, 3)
      elseif line.cells[i] then
         line.cells[i]:ReleaseCell()
      end
      line.cells[i] = false
   end
   
   -- Create the cell and anchor it
   local cell = provider:AcquireCell(self)
   cell:SetPoint("LEFT", leftColumn, "LEFT", 0, 0)
   cell:SetPoint("RIGHT", rightColumn, "RIGHT", 0, 0)
   cell:SetPoint("TOP", line, "TOP", 0, 0)
   cell:SetPoint("BOTTOM", line, "BOTTOM", 0, 0)
   line.cells[colNum] = cell
   
   -- Setup the cell content
   local width, height = cell:SetupCell(tooltip, value, justification or leftColumn.justification, font, ...)
   
   -- Enforce cell size
   cell:SetWidth(width)
   cell:SetHeight(height)
   cell:Show()
   
   -- Enlarge the latest column and tooltip if need be
   for i = colNum, rightColNum-1 do
      width = width - self.columns[i].width - CELL_MARGIN 
   end
   if width > rightColumn.width then
      self.width = self.width + width - rightColumn.width
      self:SetWidth(self.width)
      rightColumn.width = width
      rightColumn:SetWidth(width)
   end
   
   -- Enlarge the line and tooltip if need be
   if height > line.height then
      self.height = self.height + height - line.height
      self:SetHeight(self.height)
      line.height = height
      line:SetHeight(height)
   end
end

local function CreateLine(self, font, ...)
   local line = AcquireFrame(self)
   local lineNum = #self.lines + 1
   line:SetPoint('LEFT', self, 'LEFT', TOOLTIP_PADDING, 0)
   line:SetPoint('RIGHT', self, 'RIGHT', -TOOLTIP_PADDING, 0)
   if lineNum > 1 then
      line:SetPoint('TOP', self.lines[lineNum-1], 'BOTTOM', 0, -CELL_MARGIN)
      self.height = self.height + CELL_MARGIN
      self:SetHeight(self.height)
   else
      line:SetPoint('TOP', self, 'TOP', 0, -TOOLTIP_PADDING)
   end
   self.lines[lineNum] = line
   line.cells = line.cells or {}
   line.height = 0
   line:SetHeight(0)
   line:Show()
   for colNum = 1, self.numColumns do
      SetCell(self, lineNum, colNum, (select(colNum, ...)), font, nil, 1, labelProvider)
   end
   return lineNum
end

function tipProto:AddLine(...)
   return CreateLine(self, self.regularFont, ...)
end

function tipProto:AddHeader(...)
   return CreateLine(self, self.headerFont, ...)
end

function tipProto:SetCell(lineNum, colNum, value, font, justification, colSpan, provider, ...)
   -- Defaults arguments
   colSpan = colSpan or 1
   provider = provider or labelProvider
   font = font or self.regularFont
   
   -- Argument checking
   if type(provider.AcquireCell) ~= "function" then
      error("tooltip:SetCell(): invalid cell provider", 2)
   elseif type(colSpan) ~= "number" or colSpan < 1 then
      error("tooltip:SetCell(): invalid colspan: "..tostring(colspan), 2)
   elseif type(lineNum) ~= "number" then
      error("tooltip:SetCell(): invalid line number: "..tostring(lineNum), 2)
   elseif lineNum < 1 or lineNum > #self.lines then
      error("tooltip:SetCell(): line number out of range: "..tostring(lineNum), 2)
   elseif type(colNum) ~= "number" then
      error("tooltip:SetCell(): invalid column number: "..tostring(colNum), 2)
   elseif colNum < 1 or colNum > #self.columns then
      error("tooltip:SetCell(): column number out of range: "..tostring(colNum), 2)
   elseif colNum + colSpan - 1 > #self.columns then
      error("tooltip:SetCell(): colspan too big: "..tostring(colSpan), 2)
   end
   checkFont(font, "tooltip:SetCell()", 2)
   if justification then
      checkJustification(justification, "tooltip:SetCell()", 2)
   end
   
   return SetCell(self, lineNum, colNum, value, font, justification, colSpan, provider, ...)
end

function tipProto:GetLineCount() return #self.lines end

function tipProto:GetColumnCount() return self.numColumns end

--[[
http://www.pastey.net/99125

local function GetTipAnchor(frame) 
	    local x,y = frame:GetCenter() 
	    if not x or not y then return "TOPLEFT", "BOTTOMLEFT" end 
	    local hhalf = (x > UIParent:GetWidth()*2/3) and "RIGHT" or (x < UIParent:GetWidth()/3) and "LEFT" or "" 
	    local vhalf = (y > UIParent:GetHeight()/2) and "TOP" or "BOTTOM" 
	    return vhalf..hhalf, (vhalf == "TOP" and "BOTTOM" or "TOP")..hhalf 
	end 
	 
	local function GetOffscreen(frame) 
	    local offX, offsetX 
	    if frame and frame:GetLeft() and frame:GetLeft() * frame:GetEffectiveScale() < UIParent:GetLeft() * UIParent:GetEffectiveScale() then 
	        offX = -1; 
	        offsetX = UIParent:GetLeft() - frame:GetLeft() 
	    elseif frame and frame:GetRight() and frame:GetRight() * frame:GetEffectiveScale() > UIParent:GetRight() * UIParent:GetEffectiveScale() then 
	        offX = 1; 
	        offsetX = frame:GetRight() - UIParent:GetRight() 
	    else 
	        offX = 0; 
	        offsetX = 0; 
	    end 
	    return offX, offsetX 
	end 
	 
	 
	 
	-- lib 
	 
	-- anchoring 
	    tt:ClearAllPoints() 
	    -- get offscreenX and adjust accordingly 
	    local offX, offsetX = GetOffscreen(self) 
	    local anchorPoint1, anchorPoint2 = GetTipAnchor(self) 
	    if offX == -1 then 
	        tt:SetPoint(anchorPoint1, self, anchorPoint2, offsetX, 0) 
	    elseif offX == 1 then 
	        tt:SetPoint(anchorPoint1, self, anchorPoint2, -offsetX, 0) 
	    else 
	        tt:SetPoint(anchorPoint1, self, anchorPoint2) 
	    end  
--]]
