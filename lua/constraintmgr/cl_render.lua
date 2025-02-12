local linecol = { -- Default colors for all known constraints
    Rope = Color(150,150,0),
    Elastic = Color(255,255,0),
    Weld = Color(0,0,255),
    NoCollide = Color(0,255,0),
    AdvBallsocket = Color(0,150,255),
    Ballsocket = Color(0,255,255),
    Parent = Color(255,150,255),
    Child = Color(150,100,255),
    Axis = Color(255,0,0),
    Hydraulic = Color(200,255,0),
    WireHydraulic = Color(200,255,0),
    Pulley = Color(150,200,0),
    Muscle = Color(200,255,0),
    Winch = Color(200,255,0),
    Motor = Color(255,50,100),
    WireMotor = Color(255,50,100),
    Slider = Color(100,50,200),
    Keepupright = Color(100,255,150)
}
local col = {
    grey = Color(150,150,150,100),
    black = Color(0,0,0),
    hover_bg = Color(50,255,50,200),
    black_half = Color(0,0,0,150),
    black_220 = Color(0,0,0,220),
    selected0 = Color(255,0,0),
    selected1 = Color(255,255,255),
    green = Color(0,255,0),
    badtext = Color(220,100,100),
    panel_fg = Color(20,20,20)
}

local textcol = {}
local scr,cur,center = Vector(),Vector(),Vector()
CMgr_TextWidth = {}
CMgr_FreezeRender = false

local GetPlayerBool = CMgr.GetPlayerBool

local function CalcScale(l) return l and (0.1 + ((math.min(l,512) * 1) ^ 0.8) * 0.01) or 1 end

local function DrawBeam(pos1,pos2,c,scale,thin)
    scale = scale * LocalPlayer():GetInfoNum("constraintmgr_scale_line",0)
    if scale > 0 then
        render.SetColorMaterialIgnoreZ()
        render.StartBeam(2)
        render.AddBeam(pos1,0.3 * scale,0,c)
        render.AddBeam(pos2,1 * scale,0,c)
        render.EndBeam()
    end
    if thin then render.DrawLine(pos1,pos2,c) end
end

CMgr.InitType = function(str) -- Calculate and cache visuals for a constraint type
    if CMgr_TextWidth[str] then return end
    linecol[str] = linecol[str] or Color(255,0,200)
    local mycol = {ColorToHSV(linecol[str])}
    textcol[str] = HSVToColor(mycol[1],mycol[2] * 0.5,(mycol[3] + 1) * 0.5)

    local width = 0
    for c in str:gmatch(".") do
        width = width + (string.find(c,"[ .Iijl]",1) and 0.5 or 1)
        width = width + (string.find(c,"[A-Zdp]",1) and 0.25 or 0)
        width = width + (string.find(c,"[Ww]",1) and 0.55 or 0)
    end
    CMgr_TextWidth[str] = width
end
for k in pairs(linecol) do CMgr.InitType(k) end

local function IsValidW(ent)
    if ent == game.GetWorld() then return true end
    return IsValid(ent)
end
local Think = function() -- Calculating constraint worldpos and relative tooltip positions
    if #CMgr_Constraints == 0 then return end
    local v
    for k,g in ipairs(CMgr_ConstraintGroups) do
        v = g[1]
        if not v then break end
        if not CMgr_FreezeRender or not v.WPos1 then
            for l,w in ipairs(g) do
                if not IsValidW(w.Ent1) or not IsValidW(w.Ent2) then table.remove(CMgr_Constraints,k) break end
                w.WPos1 = (w.Ent1:IsWorld() and w.LPos1 == vector_origin) and (w.Ent2:GetPos() + Vector(0,0,-32)) or w.Ent1:LocalToWorld(w.LPos1)
                w.WPos2 = (w.Ent2:IsWorld() and w.LPos2 == vector_origin) and (w.Ent1:GetPos() + Vector(0,0,-32)) or w.Ent2:LocalToWorld(w.LPos2)
            end
            v.WPos1 = v.WPos1 and v.WPos1 or vector_origin
            v.WPos2 = v.WPos2 and v.WPos2 or vector_origin
        end
        if (not CMgr_FreezeRender or not v.WPos) and v.WPos1 then
            v.WPos = ((v.WPos1 + v.WPos2) * 0.5)
            v.Length = v.WPos1:Distance(v.WPos2)
            for l,b in ipairs(g) do
                b.WPos = v.WPos
            end
        end
        v.mins = v.mid and {x = v.mid.x-v.size.x * 0.5,y = v.mid.y-v.size.y * 0.5} or {x = 9999,y = 9999}
        v.maxs = {x = v.mins.x + v.size.x, y = v.mins.y + v.size.y}
        if GetPlayerBool("overlap") then continue end -- Skip overlap checking
        v.movedr = 0
        v.movedl = 0
        for i = 1,#CMgr_ConstraintGroups * 0.5 do
            for l,b in ipairs(CMgr_ConstraintGroups) do
                b = b[1]
                if v == b then break end
                if not b.render then continue end
                if not (v.maxs.y > b.mins.y and v.mins.y < b.maxs.y) then continue end
                local movex = 0
                local movey = 0
                if v.mins.x <= b.maxs.x and v.mins.x >= b.mins.x then
                    movex = b.maxs.x - v.mins.x + 2
                    v.movedr = v.movedr + 1
                elseif v.maxs.x >= b.mins.x and v.mins.x <= b.mins.x then
                    movex = b.mins.x - v.maxs.x - 2
                    v.movedl = v.movedl + 1
                end
                if v.movedl > 0 and movex > 0 or v.movedr > 4 then
                    movey = false
                    v.movedr = v.movedr - 1
                elseif v.movedr > 0 and movex < 0 or v.movedl > 4 then
                    movey = true
                    v.movedl = v.movedl - 1
                end

                if movey == 0 then
                    v.mins.x = v.mins.x + movex
                    v.maxs.x = v.maxs.x + movex
                else
                    movey = movey and (b.mins.y - v.maxs.y - 2) or (b.maxs.y - v.mins.y + 2)
                    v.mins.y = v.mins.y + movey
                    v.maxs.y = v.maxs.y + movey
                end
            end
        end
    end
end

local PreDrawEffects = function() -- Render lines/beams
    if #CMgr_Constraints == 0 then return end
    local scale = 1
    for k,v in ipairs(CMgr_ConstraintGroups) do
        local n = #v
        scale = CalcScale(v[1].Length)
        for l,b in ipairs(v) do
            if not b.WPos1 then continue end
            DrawBeam(b.WPos1,b.WPos2,linecol[b.Type],scale * (1 + (n-l) * 2),l == 1)
        end
    end
    if CMgr_Hovered then
        local sel = CMgr_ConstraintGroups[CMgr_Hovered][CMgr_Selected]
        local v = CMgr_ConstraintGroups[CMgr_Hovered][1]
        scale = CalcScale(v.Length)
        DrawBeam(sel.WPos1,sel.WPos2,(CurTime() % 1 < 0.5) and col.selected0 or col.selected1,scale * (1 + (#CMgr_ConstraintGroups[CMgr_Hovered]-CMgr_Selected) * 2),true)
    end
end

local HUDPaint = function() -- Render tooltips
    if #CMgr_Constraints == 0 then
        if CMgr_LastHover then
            --tool:SetStage(0)
            CMgr_LastHover = nil
        end
        return
    end
    if CMgr_LastHover ~= CMgr_Hovered then
        CMgr_Selected = 1
        --if CMgr_Hovered then tool:SetStage(1) else tool:SetStage(0) end
    end
    CMgr_LastHover = CMgr_Hovered
    CMgr_Hovered = nil
    scr.x = ScrW() scr.y = ScrH()
    cur.x = scr.x * 0.5 cur.y = scr.y * 0.5
    --cur.x,cur.y = input.GetCursorPos()
    for k,v in ipairs(CMgr_ConstraintGroups) do
        v = v[1]
        if not v.WPos then continue end
        v.mid = v.WPos:ToScreen()
        if CMgr_Active and cur.x > v.mins.x and cur.x < v.maxs.x and
        cur.y > v.mins.y and cur.y < v.maxs.y then
            CMgr_Hovered = k
        end
    end
    for k,v in ipairs(CMgr_Constraints) do
        if not v.Ent1:IsWorld() and not v.Ent2:IsWorld() then continue end
        if not v.WPos1 or not v.WPos2 then return end
        local tp = v.Ent1:IsWorld() and v.WPos1:ToScreen() or v.WPos2:ToScreen()
        --draw.RoundedBox(0,tp.x-9,tp.y-9,19,18,Color(100,100,100,150)) -- Draw a box around the W
        --draw.RoundedBox(0,tp.x-8,tp.y-8,17,16,Color(0,0,0,200))
        draw.SimpleTextOutlined("W","ChatFont",tp.x-7,tp.y-12,linecol[v.Type],TEXT_ALIGN_LEFT,TEXT_ALIGN_TOP,2,col.black_220)
    end
    for k,v in ipairs(CMgr_ConstraintGroups) do
        local mins = v[1].mins
        if not mins then continue end
        local size = v[1].size
        v[1].render = true
        if GetPlayerBool("cull") and v[1].WPos then
            local s = v[1].WPos:ToScreen()
            center.x = s.x--mins.x + size.x*0.5
            center.y = s.y--mins.y + size.y*0.5
            if center:Distance2D(cur) > scr.y * 0.25 then v[1].render = false continue end
        end
        draw.RoundedBox(0,mins.x,mins.y,size.x,size.y,(CMgr_Hovered == k) and col.hover_bg or col.grey)
        draw.RoundedBox(0,mins.x + 2,mins.y + 2,size.x - 4,size.y - 4,(CMgr_Hovered == k) and col.black_220 or col.black_half)
        for l,b in ipairs(v) do
            local c = (CMgr_Selected == l and CMgr_Hovered == k) and ((CurTime() % 1 < 0.5) and col.selected0 or col.selected1) or textcol[b.Type]
            draw.SimpleTextOutlined(b.Type,"ChatFont",mins.x + 4,mins.y + l * 15 - 14,c,TEXT_ALIGN_LEFT,TEXT_ALIGN_TOP,1,col.black_half)
        end
    end
end

function CMgr.StartRender()
    hook.Add("Think","constraintmgr_renderthink",Think)
    hook.Add("HUDPaint","constraintmgr_renderhud",HUDPaint)
    hook.Add("PreDrawEffects","constraintmgr_render3d",PreDrawEffects)
end
function CMgr.StopRender()
    hook.Remove("Think","constraintmgr_renderthink")
    hook.Remove("HUDPaint","constraintmgr_renderhud")
    hook.Remove("PreDrawEffects","constraintmgr_render3d")
end

CMgr.Inspect = {}
local modified
local window,panel,wait
local items = {}

local function ApplyChanges(self) -- replace constraint on server with updated properties
    wait = window:Add("DPanel")
    wait:CopyBounds(panel)
    wait:SetCursor("hourglass")
    wait:SetPaintBackground(false)
    self:SetEnabled(false)
    net.Start("constraintmgr_replace")
    net.WriteUInt(CMgr.Inspect.id,8)
    CMgr.WriteTable(modified)
    net.SendToServer()
    net.Receive("constraintmgr_replace",function()
        local result = net.ReadUInt(2)
        local results = {
            [0] = {"buttons/button2.wav","#tool.constraintmgr.notif.update_fail",NOTIFY_ERROR},
            [1] = {"buttons/button14.wav","#tool.constraintmgr.notif.update_success",NOTIFY_GENERIC},
            [2] = {"buttons/lightswitch2.wav","#tool.constraintmgr.notif.update_cancel",NOTIFY_HINT}
        }
        if GetPlayerBool("sound") then LocalPlayer():EmitSound(results[result][1],nil,nil,0.5) end
        notification.AddLegacy(results[result][2],results[result][3],result == 2 and 3 or 2)
        window:Remove()
    end)
end
local function ModifiedEntry(item,value) -- typed something in one of the text boxes
    if not modified then
        modified = {}
        local applybutton = panel:Add("DButton")
        applybutton:SetText("Apply Changes")
        applybutton:DockMargin(4,4,4,-2)
        applybutton:Dock(TOP)
        applybutton.DoClick = ApplyChanges
        local cancelbutton = panel:Add("DButton")
        cancelbutton:SetText("Cancel")
        cancelbutton:DockMargin(4,4,4,-2)
        cancelbutton:Dock(TOP)
        cancelbutton.DoClick = function()
            if GetPlayerBool("sound") then LocalPlayer():EmitSound("buttons/button15.wav",nil,nil,0.3) end
            window:Remove()
        end
    end
    local field = string.sub(item.label:GetText(),1,-4)
    if field == "color" then
        local c = string.Split(value," ")
        item.picker:SetColor({r = tonumber(c[1]) or 0,g = tonumber(c[2]) or 0,b = tonumber(c[3]) or 0,a = 255})
    end
    if field == "material" then
        item.icon:SetMaterial(value)
    end
    item:SetBGColor(value == CMgr.Inspect.tbl[field] and color_white or col.hover_bg)
    modified[field] = value
    if items.amplitude then
        if field == "Length1" then
            items.Length2.entry:SetValue(tostring(tonumber(value) + tonumber(items.amplitude.entry:GetValue())))
        end
        if field == "amplitude" then
            items.Length2.entry:SetValue(tostring(tonumber(value) + tonumber(items.Length1.entry:GetValue())))
        end
        if field == "Length2" then
            local calc = tostring(tonumber(value) - tonumber(items.Length1.entry:GetValue()))
            if calc == items.amplitude.entry:GetValue() then return end
            items.amplitude.entry:SetValue(calc)
        end
    end
    if CMgr.Inspect.tbl.Type == "Hydraulic" then
        if field == "fwd_speed" then
            local curval = items.bwd_speed.entry:GetValue()
            if value == curval then return end
            items.bwd_speed.entry:SetValue(value)
        elseif field == "bwd_speed" then
            items.fwd_speed.entry:SetValue(value)
        end
    end
    if field == "length" then modified.addlength = tonumber(value) and 0 or nil end
end
local function LoadInspect(tbl)
    CMgr.Inspect.tbl = tbl
    items = {}
    window:SetTitle("Constraint info for " .. CMgr.Inspect.const.Type .. " [" .. tostring(CMgr.Inspect.id) .. "]")
    local copied
    for k,v in SortedPairs(tbl) do
        if CMgr.GetType(v) == "table" or k[1] == "_" then continue end
        items[k] = panel:Add("EditablePanel")
        items[k]:SetHeight(20)
        items[k]:DockPadding(4,0,4,0)
        items[k]:DockMargin(0,4,0,-2)
        items[k].PerformLayout = function(self,w,h)
            local entry = self.entry
            local label = self.label
            if entry:GetName() == "DCheckBox" then
                entry:DockMargin(0,0,math.min(196 + (w-280) * 0.25,w * 0.8 - 19),0)
            else
                entry:SetWidth(math.min(215 + (w-280) * 0.25,w * 0.8))
            end
            label:SetWidth(math.min(100,w * 0.23))
        end
        items[k]:Dock(TOP)

        items[k].label = items[k]:Add("DLabel")
        items[k].label:SetText(k .. " = ")
        items[k].label:SetColor(col.panel_fg)
        items[k].label:SetWidth(100)
        items[k].label:Dock(LEFT)

        local isfakebool = CMgr.ValidValues[k] == "y"
        if type(v) == "boolean" or isfakebool then
            items[k].entry = items[k]:Add("DCheckBox")
            items[k].entry:SetChecked(tobool(v))
            items[k].entry.OnChange = function(_,bVal) ModifiedEntry(items[k],isfakebool and (bVal == 0 and 0 or 1) or bVal) end
            items[k].entry:SetWidth(20)
            items[k].entry:Dock(RIGHT)
            continue
        end
        if string.find(string.lower(k),"key") or string.find(string.lower(k),"bind") then
            items[k].entry = items[k]:Add("DBinder")
            items[k].entry:SetValue(v)
            items[k].entry.OnChange = function(_,iNum) ModifiedEntry(items[k],iNum) end
            items[k].entry:Dock(RIGHT)
            continue
        end
        items[k].entry = items[k]:Add("DTextEntry")
        items[k].entry:SetText(tostring(v))
        items[k].entry.default_text = tostring(v)
        items[k].entry:SetNumeric(type(v) ~= "string")
        if type(v) == "string" and #string.Split(v," ") == 3 then
            items[k].entry.AllowInput = function(_,char)
                return string.find("0123456789. -",char) == nil
            end
        end
        if string.find("Entity Player",type(v)) or string.find("Type Constraint",k) then
            items[k].entry:SetKeyboardInputEnabled(false)
        else
            items[k].entry:SetUpdateOnType(true)
            items[k].entry.OnValueChange = function(_,value) ModifiedEntry(items[k],value) end
            items[k].entry:SetHistoryEnabled(true)
            items[k].entry:AddHistory(tostring(v))
            if k == "length" then
                items[k].entry:AddHistory(tostring(tbl._curlength))
                items[k].entry:SetTooltip("#tool.constraintmgr.tooltip.lengthpreset")
                if v == -1 then
                    items[k].entry:SetText("")
                    items[k].entry:SetPlaceholderText(tostring(tbl._curlength))
                    items[k].entry:SetPlaceholderColor(col.badtext)
                    items[k].entry:SetTooltip("#tool.constraintmgr.tooltip.placeholderwarn")
                end
            end
        end
        items[k].entry:Dock(RIGHT)
        if type(v) == "Entity" and IsValid(v) then -- Icon for props
            local model = v:GetModel() or ""
            if not util.IsValidModel(model) then continue end
            items[k].icon = items[k].entry:Add("SpawnIcon")
            items[k].icon:SetModel(model)
            items[k].icon:SetWidth(33)
            items[k].icon:DockMargin(0,0,1,0)
            items[k].icon:Dock(RIGHT)
            items[k].icon:SetTooltip("[Click to copy] " .. model)
            items[k].icon._itemindex = k
            items[k].icon.DragMousePress = function(self,code) -- Copy model to clipboard
                if code ~= MOUSE_LEFT then return end
                SetClipboardText(model)
                if copied then copied:Remove() end
                copied = self:Add("DPanelOverlay")
                copied:SetColor(col.green)
                if GetPlayerBool("sound") then LocalPlayer():EmitSound("buttons/button14.wav",nil,120,0.3) end
            end
            continue
        end
        if k == "color" then -- Color picker
            --local c = string.Split(v," ")
            items[k].picker = items[k].entry:Add("DColorButton")
            --items[k].picker:SetColor({r = c[1] or 0,g = c[2] or 0,b = c[3] or 0,a = 255})
            items[k].picker:SetColor(v)
            items[k].picker:SetWidth(30)
            items[k].picker:DockMargin(0,1,1,1)
            items[k].picker:Dock(RIGHT)
            continue
        end
        if k == "material" then -- Icon for rope material
            items[k].icon = items[k].entry:Add("DImage")
            items[k].icon:SetMaterial(v)
            items[k].icon:SetWidth(16)
            items[k].icon:DockMargin(0,0,2,0)
            items[k].icon:Dock(RIGHT)
            continue
        end
        if k == "Constraint" then
            items[k].entry:SetTooltip("[Serverside entity]")
            continue
        end
    end
    hook.Add("PreDrawHalos","constraintmgr_model_halo",function() -- Draw halo on hovered prop model
        for k,v in pairs(items) do
            if not v.icon then continue end
            if v.icon:IsHovered() then
                if not IsValid(tbl[k]) then break end
                halo.Add({tbl[k]},col.green,4,4,1,true,true)
            end
        end
    end)
end

CMgr.InspectPopup = function(id,const) -- Popup window with constraint info
    if not const then return end
    if const.Type == "Parent" or const.Type == "Child" then return end
    items = {}
    modified = nil
    CMgr.Inspect.id = id
    CMgr.Inspect.const = const
    if IsValid(window) then
        window:Remove()
    end
    window = vgui.Create("DFrame")
    window.OnRemove = function() hook.Remove("PreDrawHalos","constraintmgr_model_halo") end
    local sw = ScrW()
    local sh = ScrH()
    --sw = 640 sh = 480
    window:SetSize(280 + sw * 0.08,360 + sh * 0.2) -- 480p-friendly! :)
    window:SetSizable(true)
    window:SetMinimumSize(180,81)
    window:Center()
    window:MakePopup()
    panel = window:Add("DScrollPanel")
    panel:Dock(FILL)
    local schemefunc = panel.ApplySchemeSettings
    panel.ApplySchemeSettings = function(...)
        schemefunc(...)
        panel:SetBGColor(color_white)
        panel:SetPaintBackgroundEnabled(true)
    end
    wait = panel:Add("DPanel")
    wait:Dock(FILL)
    wait:SetHeight(326 + sh * 0.2)
    wait:SetCursor("hourglass")
    net.Start("constraintmgr_tbl_single") net.WriteUInt(id,8) net.SendToServer()
    net.Receive("constraintmgr_tbl_single",function()
        tbl = CMgr.ReadTable()
        if tbl._curlength and not tbl.length and not tbl.Length1 then tbl.length = -1 end
        wait:Remove()
        LoadInspect(tbl)
    end)
end