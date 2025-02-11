TOOL.Category = "Constraints"
TOOL.Name = "#tool.constraintmgr.name"

TOOL.ClientConVar["persist"] = 0
TOOL.ClientConVar["parents"] = 0
TOOL.ClientConVar["parents_nophys"] = 0
TOOL.ClientConVar["sound"] = 1
TOOL.ClientConVar["cull"] = 1
TOOL.ClientConVar["overlap"] = 0
TOOL.ClientConVar["scale_line"] = 1

local Think,HUDPaint,PreDrawEffects,PlayerBindPress,KeyPress,KeyRelease -- client hook functions

local function GetPlayerBool(ply,property) return ply:GetInfoNum("constraintmgr_" .. property,0) > 0 end

local tool
local toolactive = false

if CLIENT then
    TOOL.Information = {
        {name = "left_0", stage = 0},
        {name = "left_1", stage = 1},
        {name = "right"},
        {name = "reload", stage = 1},
        {name = "alt",icon = "icon16/control_pause.png"}
    }
    local t = "tool.constraintmgr."
    language.Add(t .. "name","Constraint Manager")
    language.Add(t .. "desc","View and modify constraints")
    language.Add(t .. "left_0","Select entity")
    language.Add(t .. "left_1","Inspect constraint")
    language.Add(t .. "right","Clear entity")
    language.Add(t .. "reload","Remove highlighted constraint")
    language.Add(t .. "alt","Alt: Freeze display")

    language.Add(t .. "var.persist","Keep constraints visible when switching tools")
    language.Add(t .. "var.parents","Show parent/child relations as constraints")
    language.Add(t .. "var.parents_nophys","Show children without physics")
    language.Add(t .. "var.sound","Enable tool sounds")
    language.Add(t .. "var.cull","Hide constraints far from crosshair")
    language.Add(t .. "var.overlap","Performance: Allow tooltip overlap")
    language.Add(t .. "tooltip.overlap","Checking this may improve FPS in extreme cases!")
    language.Add(t .. "var.scale_line","Line scale")
    language.Add(t .. "tooltip.scale_line","Only thin lines will be rendered if set to 0.")

    language.Add(t .. "notif.update_fail","Failed to update constraint!")
    language.Add(t .. "notif.update_success","Constraint updated!")
    language.Add(t .. "notif.update_cancel","Constraint update cancelled (no change)")

    language.Add(t .. "tooltip.fakeconstraint","Constraint info is unavailable for these,\nas they do not represent real constraints.")
    language.Add(t .. "tooltip.lengthpreset","Press up arrow to recall constraint's\ncurrent physical length")
    language.Add(t .. "tooltip.placeholderwarn","This value was calculated automatically.\nThings will break if this constraint is updated while unfrozen!")

    function TOOL.BuildCPanel(panel)
        tool = LocalPlayer():GetTool("constraintmgr")
        t = "#" .. t
        local c
        panel:CheckBox(t .. "var.persist","constraintmgr_persist").OnChange = function(_,val)
            if not val and not toolactive then
                timer.Create("wait_persist",0.02,1,function()
                    net.Start("constraintmgr_clear")
                    net.SendToServer()
                    if tool then tool:Holster() end
                end)
            end
        end

        local checkno
        c = panel:CheckBox(t .. "var.parents","constraintmgr_parents")
        c.OnChange = function(_,val)
            timer.Create("wait_parent",0.02,1,function()
                checkno:SetEnabled(val)
                net.Start("constraintmgr_tbl")
                net.SendToServer()
            end)
        end
        c:SetTooltip("#tool.constraintmgr.tooltip.fakeconstraint")
        checkno = panel:CheckBox(t .. "var.parents_nophys","constraintmgr_parents_nophys")
        checkno.OnChange = function(_,val)
            timer.Create("wait_parent",0.02,1,function()
                net.Start("constraintmgr_tbl")
                net.SendToServer()
            end)
        end
        checkno:SetTooltip("Holograms, etc.")

        c = vgui.Create("DPanel",panel) c:SetHeight(1) panel:AddItem(c)

        panel:CheckBox(t .. "var.cull","constraintmgr_cull")
        panel:CheckBox(t .. "var.sound","constraintmgr_sound")
        panel:CheckBox(t .. "var.overlap","constraintmgr_overlap"):SetTooltip(t .. "tooltip.overlap")
        panel:NumSlider(t .. "var.scale_line","constraintmgr_scale_line",0,3,1):SetTooltip(t .. "tooltip.scale_line")
    end

    net.Receive("constraintmgr_notify",function()
        chat.AddText(net.ReadString())
    end)

    local linecol = { -- Default colors for some constraints
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
    local textcol = {}
    local textwidth = {}

    local col = {
        grey = Color(150,150,150,100),
        black = Color(0,0,0),
        hover_bg = Color(50,255,50,200),
        black_half = Color(0,0,0,150),
        black_220 = Color(0,0,0,220),
        selected0 = Color(255,0,0),
        selected1 = Color(255,255,255),
        green = Color(0,255,0),
        badtext = Color(220,100,100)
    }
    local hovered,selection = nil,0
    local lasthover = nil
    local freeze = false

    local function InitType(str) -- Initial setup for constraint visuals
        if textwidth[str] then return end
        linecol[str] = linecol[str] or Color(255,0,200)
        local mycol = {ColorToHSV(linecol[str])}
        textcol[str] = HSVToColor(mycol[1],mycol[2] * 0.5,(mycol[3] + 1) * 0.5)

        local width = 0
        for c in str:gmatch(".") do
            width = width + (string.find(c,"[ .Iijl]",1) and 0.5 or 1)
            width = width + (string.find(c,"[A-Zdp]",1) and 0.25 or 0)
            width = width + (string.find(c,"[Ww]",1) and 0.55 or 0)
        end
        textwidth[str] = width
    end

    for k in pairs(linecol) do InitType(k) end

    local constraints = {}
    local constraintGroups = {}

    local scr,cur,center = Vector(),Vector(),Vector()

    local window

    local function GroupConstraints() -- Sort constraints into tables if they share the same entities and positions
        hovered, selection = nil,1
        constraintGroups = {}
        for k,v in ipairs(constraints) do
            if v.group then continue end
            for l,b in ipairs(constraints) do
                if l == k then continue end
                if not ((v.Ent1 == b.Ent1 and v.Ent2 == b.Ent2) or (v.Ent1 == b.Ent2 and v.Ent2 == b.Ent1)) then continue end
                if not ((v.LPos1 == b.LPos1 and v.LPos2 == b.LPos2) or (v.LPos1 == b.LPos2 and v.LPos2 == b.LPos1)) then continue end
                if b.group then
                    table.insert(constraintGroups[b.group],v)
                    v.group = b.group
                else
                    v.group = table.insert(constraintGroups,{v,b})
                    b.group = v.group
                end
                break
            end
        end
        local count = 0
        for k,v in ipairs(constraints) do -- Calculate longest name for tooltip rendering
            if v.group then
                local widest = constraintGroups[v.group][1].widest
                if widest then
                    if textwidth[v.Type] > widest then
                        constraintGroups[v.group][1].widest = textwidth[v.Type]
                    end
                else
                    constraintGroups[v.group][1].widest = textwidth[v.Type]
                end
                continue
            end
            v.group = table.insert(constraintGroups,{v})
            v.widest = textwidth[v.Type]
            count = count + 1
        end
        for k,g in ipairs(constraintGroups) do
            local v = g[1]
            v.size = {x = 10 + v.widest * 9, y = 8 + #g * 15}
        end
    end

    net.Receive("constraintmgr_tbl",function() -- List of constraints from server
        local n = net.ReadUInt(8)
        local tbl = {}
        for i = 1,n do
            local id = net.ReadUInt(8)
            tbl[id] = {Index = id}
            tbl[id].Type = net.ReadString()
            InitType(tbl[id].Type)
            for j = 1,2 do
                tbl[id]["Ent" .. tostring(j)] = net.ReadEntity()
                if not net.ReadBool() then
                    tbl[id].LPos1 = vector_origin
                    tbl[id].LPos2 = vector_origin
                    continue
                end
                local idx = "LPos" .. tostring(j)
                if net.ReadBool() then
                    tbl[id][idx] = net.ReadVector()
                else -- 3 floats to a vector, in case of worldpos (big vectors get messed up)
                    tbl[id][idx] = Vector(
                        net.ReadFloat(),
                        net.ReadFloat(),
                        net.ReadFloat()
                    )
                end
            end
        end
        constraints = tbl
        GroupConstraints()
    end)
    local function CMgrActive(self)
        local a = net.ReadBool()
        if not LocalPlayer() then timer.Simple(5,CMgrActive(self)) return false end
        tool = LocalPlayer():GetTool("constraintmgr")
        if not tool then return end
        if a then tool:Deploy() else tool:Holster() end
    end
    net.Receive("constraintmgr_active",CMgrActive)

    local function IsValidW(ent)
        if ent == game.GetWorld() then return true end
        return IsValid(ent)
    end

    function TOOL:SetStage(stage) timer.Create("setstage",0.02,1,function() self._stage = stage end) end
    function TOOL:GetStage() return self._stage or 0 end -- Override clientside Stage functions (they do nothing)

    Think = function() -- Calculating constraint worldpos and relative tooltip positions
        if #constraints == 0 then return end
        local v
        for k,g in ipairs(constraintGroups) do
            v = g[1]
            if not v then break end
            if not freeze or not v.WPos1 then
                for l,w in ipairs(g) do
                    if not IsValidW(w.Ent1) or not IsValidW(w.Ent2) then table.remove(constraints,k) break end
                    w.WPos1 = (w.Ent1:IsWorld() and w.LPos1 == vector_origin) and (w.Ent2:GetPos() + Vector(0,0,-32)) or w.Ent1:LocalToWorld(w.LPos1)
                    w.WPos2 = (w.Ent2:IsWorld() and w.LPos2 == vector_origin) and (w.Ent1:GetPos() + Vector(0,0,-32)) or w.Ent2:LocalToWorld(w.LPos2)
                end
            end
            if (not freeze or not v.WPos) and v.WPos1 then
                v.WPos = ((v.WPos1 + v.WPos2) * 0.5)
                v.Length = v.WPos1:Distance(v.WPos2)
                for l,b in ipairs(g) do
                    b.WPos = v.WPos
                end
            end
            v.mins = v.mid and {x = v.mid.x-v.size.x * 0.5,y = v.mid.y-v.size.y * 0.5} or {x = 9999,y = 9999}
            v.maxs = {x = v.mins.x + v.size.x, y = v.mins.y + v.size.y}
            if GetPlayerBool(LocalPlayer(),"overlap") then continue end -- Skip overlap checking
            v.movedr = 0
            v.movedl = 0
            for i = 1,#constraintGroups * 0.5 do
                for l,b in ipairs(constraintGroups) do
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

    local function CalcScale(l) return l and (0.1 + ((math.min(l,512) * 1) ^ 0.8) * 0.01) or 1 end

    PreDrawEffects = function() -- Render lines/beams
        if #constraints == 0 then return end
        local scale = 1
        for k,v in ipairs(constraintGroups) do
            local n = #v
            scale = CalcScale(v[1].Length)
            for l,b in ipairs(v) do
                if not b.WPos1 then continue end
                DrawBeam(b.WPos1,b.WPos2,linecol[b.Type],scale * (1 + (n-l) * 2),l == 1)
            end
        end
        if hovered then
            local sel = constraintGroups[hovered][selection]
            local v = constraintGroups[hovered][1]
            scale = CalcScale(v.Length)
            DrawBeam(sel.WPos1,sel.WPos2,(CurTime() % 1 < 0.5) and col.selected0 or col.selected1,scale * (1 + (#constraintGroups[hovered]-selection) * 2),true)
        end
    end

    HUDPaint = function() -- Render tooltips
        if not tool then return end
        if #constraints == 0 then
            if lasthover then
                tool:SetStage(0)
                lasthover = nil
            end
            return
        end
        scr.x = ScrW() scr.y = ScrH()
        cur.x = ScrW() * 0.5 cur.y = ScrH() * 0.5
        if lasthover ~= hovered then
            selection = 1
            if hovered then tool:SetStage(1) else tool:SetStage(0) end
        end
        lasthover = hovered
        hovered = nil
        for k,v in ipairs(constraintGroups) do
            v = v[1]
            if not v.WPos then continue end
            v.mid = v.WPos:ToScreen()
            if toolactive and
            cur.x > v.mins.x and cur.x < v.maxs.x and
            cur.y > v.mins.y and cur.y < v.maxs.y then
                hovered = k
            end
        end
        for k,v in ipairs(constraints) do
            if not v.Ent1:IsWorld() and not v.Ent2:IsWorld() then continue end
            if not v.WPos1 or not v.WPos2 then return end
            local tp = v.Ent1:IsWorld() and v.WPos1:ToScreen() or v.WPos2:ToScreen()
            --draw.RoundedBox(0,tp.x-9,tp.y-9,19,18,Color(100,100,100,150)) -- Draw a box around the W
            --draw.RoundedBox(0,tp.x-8,tp.y-8,17,16,Color(0,0,0,200))
            draw.SimpleTextOutlined("W","ChatFont",tp.x-7,tp.y-12,linecol[v.Type],TEXT_ALIGN_LEFT,TEXT_ALIGN_TOP,2,col.black_220)
        end
        for k,v in ipairs(constraintGroups) do
            local mins = v[1].mins
            if not mins then continue end
            local size = v[1].size
            v[1].render = true
            if GetPlayerBool(LocalPlayer(),"cull") then
                local s = v[1].WPos:ToScreen()
                center.x = s.x--mins.x + size.x*0.5
                center.y = s.y--mins.y + size.y*0.5
                if center:Distance2D(cur) > scr.y * 0.25 then v[1].render = false continue end
            end
            draw.RoundedBox(0,mins.x,mins.y,size.x,size.y,(hovered == k) and col.hover_bg or col.grey)
            draw.RoundedBox(0,mins.x + 2,mins.y + 2,size.x - 4,size.y - 4,(hovered == k) and col.black_220 or col.black_half)
            for l,b in ipairs(v) do
                local c = (selection == l and hovered == k) and ((CurTime() % 1 < 0.5) and col.selected0 or col.selected1) or textcol[b.Type]
                draw.SimpleTextOutlined(b.Type,"ChatFont",mins.x + 4,mins.y + l * 15 - 14,c,TEXT_ALIGN_LEFT,TEXT_ALIGN_TOP,1,col.black_half)
            end
        end
    end

    local function Inspect(id) -- Popup window with constraint info
        local const = constraints[id]
        if not const then return end
        if const.Type == "Parent" or const.Type == "Child" then return end
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
        window:SetMinWidth(180)
        window:SetMinHeight(81)
        window:Center()
        window:MakePopup()
        local panel = window:Add("DScrollPanel")
        local bg = color_white
        local fg = Color(20,20,20)
        panel:Dock(FILL)
        local items = {}
        local schemefunc = panel.ApplySchemeSettings
        panel.ApplySchemeSettings = function(...)
            schemefunc(...)
            panel:SetBGColor(bg)
            panel:SetPaintBackgroundEnabled(true)
        end
        local wait = panel:Add("DPanel")
        --wait:SetSize(window:GetSize())
        wait:Dock(FILL)
        wait:SetHeight(326 + sh * 0.2)
        wait:SetCursor("hourglass")
        net.Start("constraintmgr_tbl_single") net.WriteUInt(id,8) net.SendToServer()
        local tbl = {}
        local modified
        local function WriteSmartTable(nt)
            net.WriteUInt(table.Count(nt),6)
            for k,v in pairs(nt) do
                if v == "" then continue end
                if v == tbl[k] then continue end
                if string.find(k,"Pos") or string.find(k,"Axis") then
                    v = Vector(v)
                    net.WriteString("vec," .. k)
                    net.WriteFloat(v[1]) net.WriteFloat(v[2]) net.WriteFloat(v[3])
                    continue
                end
                if string.lower(k) == "ang" then
                    v = Angle(v)
                    net.WriteString("ang," .. k)
                    net.WriteAngle(v)
                    continue
                end
                if string.lower(k) == "color" then
                    local c = {}
                    local nc = string.Split(v," ")
                    for i = 1, 3 do
                        c[i] = tonumber(nc[i]) or 0
                    end
                    v = Color(unpack(c))
                    net.WriteString("col," .. k)
                    net.WriteColor(v,false)
                    continue
                end
                v = tonumber(v) or v
                if type(tbl[k]) == "number" and type(v) ~= "number" then continue end
                if type(v) == "number" then
                    if v % 1 ~= 0 then
                        net.WriteString("flt," .. k)
                        net.WriteFloat(v)
                    else
                        net.WriteString("int," .. k)
                        net.WriteInt(math.Clamp(v,-8388608,8388607),24)
                    end
                    continue
                end
                if --[[v == "true" or v == "false"]] type(v) == "boolean" then
                    --v = tobool(v)
                    net.WriteString("boo," .. k)
                    net.WriteBool(v)
                    continue
                end
                net.WriteString("str," .. k)
                net.WriteString(v)
            end
            net.WriteString("end")
        end
        local function ApplyChanges(self) -- replace constraint on server with updated properties
            wait = window:Add("DPanel")
            wait:CopyBounds(panel)
            wait:SetCursor("hourglass")
            wait:SetPaintBackground(false)
            self:SetEnabled(false)
            net.Start("constraintmgr_replace")
            net.WriteUInt(id,8)
            WriteSmartTable(modified)
            net.SendToServer()
            net.Receive("constraintmgr_replace",function()
                local result = net.ReadUInt(2)
                local results = {
                    [0] = {"buttons/button2.wav","#tool.constraintmgr.notif.update_fail",NOTIFY_ERROR},
                    [1] = {"buttons/button14.wav","#tool.constraintmgr.notif.update_success",NOTIFY_GENERIC},
                    [2] = {"buttons/lightswitch2.wav","#tool.constraintmgr.notif.update_cancel",NOTIFY_HINT}
                }
                if GetPlayerBool(LocalPlayer(),"sound") then LocalPlayer():EmitSound(results[result][1],nil,nil,0.5) end
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
                    if GetPlayerBool(LocalPlayer(),"sound") then LocalPlayer():EmitSound("buttons/button15.wav",nil,nil,0.3) end
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
            item:SetBGColor(value == tbl[field] and bg or col.hover_bg)
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
            if tbl.Type == "Hydraulic" then
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
        net.Receive("constraintmgr_tbl_single",function()
            --tbl = net.ReadTable()
            tbl = {}
            local count = net.ReadUInt(6)
            for i = 1,count do
                local k,v = net.ReadString(), net.ReadString()
                if k == "end" or not v then return end
                v = tonumber(v) or v
                if tostring(tobool(v)) == v then v = tobool(v) end
                tbl[k] = v
            end
            window:SetTitle("Constraint info for " .. const.Type .. " [" .. tostring(id) .. "]")
            wait:Remove()
            local copied
            if tbl._curlength and not tbl.length and not tbl.Length1 then tbl.length = -1 end
            for k,v in SortedPairs(tbl) do
                if type(v) == "table" or k[1] == "_" then continue end
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
                items[k].label:SetColor(fg)
                items[k].label:SetWidth(100)
                items[k].label:Dock(LEFT)

                local isfakebool = string.find("onlyrotation nocollide fixed toggle",string.lower(k)) and true or false
                if type(v) == "boolean" or isfakebool then
                    items[k].entry = items[k]:Add("DCheckBox")
                    items[k].entry:SetChecked(tobool(v))
                    items[k].entry.OnChange = function(_,bVal) ModifiedEntry(items[k],isfakebool and (bVal and 1 or 0) or bVal) end
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
                    if not util.IsValidProp(model) then continue end
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
                        if GetPlayerBool(LocalPlayer(),"sound") then LocalPlayer():EmitSound("buttons/button14.wav",nil,120,0.3) end
                    end
                    continue
                end
                if k == "color" then -- Color picker
                    local c = string.Split(v," ")
                    items[k].picker = items[k].entry:Add("DColorButton")
                    items[k].picker:SetColor({r = c[1] or 0,g = c[2] or 0,b = c[3] or 0,a = 255})
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
        end)
    end

    PlayerBindPress = function(ply,bind,pressed) -- Detect clicks/scrolls
        if IsFirstTimePredicted() then return end -- Seems to break stuff if you check for (not IsFirstTimePredicted())
        if not toolactive then return end
        if not pressed then return end
        if not hovered then return end
        if bind == "+attack" then
            if #constraintGroups[hovered] == 1 or selection == 0 then
                selection = 1
            end
            if GetPlayerBool(LocalPlayer(),"sound") then
                local ty = constraintGroups[hovered][selection].Type
                LocalPlayer():EmitSound((ty == "Parent" or ty == "Child") and "buttons/lightswitch2.wav" or "buttons/button9.wav",nil,100,0.5)
            end
            Inspect(constraintGroups[hovered][selection].Index)
            return true
        end
        local scroll
        if bind == "invnext" then scroll = 1 elseif bind == "invprev" then scroll = -1 end
        if scroll then
            if GetPlayerBool(LocalPlayer(),"sound") then LocalPlayer():EmitSound("weapons/pistol/pistol_empty.wav",nil,120,0.3) end
            selection = selection + scroll
            if selection > #constraintGroups[hovered] then selection = 1 end
            if selection < 1 then selection = #constraintGroups[hovered] end
            return true
        end
        if bind == "+reload" then
            net.Start("constraintmgr_remove")
            net.WriteUInt(constraintGroups[hovered][selection].Index,8)
            net.SendToServer()
            LocalPlayer():EmitSound("buttons/button15.wav",nil,100,0.8)
            if #constraintGroups[hovered] <= 1 then hovered = nil end
            return false
        end
    end
    KeyPress = function(ply,key)
        if not toolactive then return end
        if key == IN_WALK then freeze = true end
    end
    KeyRelease = function(ply,key)
        if not toolactive then return end
        if key == IN_WALK then freeze = false end
    end
end

local Notify,SendTable,SendTableSingle
function TOOL:Clear()
    self:ClearObjects()
    if CLIENT then return end
    self:GetOwner().constraintmgr_selected = nil
    SendTable(self:GetOwner(),{})
    hook.Remove("PreUndo","constraintmgr_undo_" .. self:GetOwner():UserID())
end
local function CalcConstraints(ply,ent) -- Get table of constraints, and include parent/child relations
    if not IsValid(ent) then ply:GetTool("constraintmgr"):Clear() return {},0,0 end
    local tbl = constraint.GetTable(ent)
    for k,v in pairs(tbl) do
        if not v.Type then table.remove(tbl,k) end -- ignore pseudo constraints (hydraulic sliders)
    end
    local numconst = table.Count(tbl)
    local numchild = 0
    if GetPlayerBool(ply,"parents") then
        if IsValid(ent:GetParent()) then table.insert(tbl,{Type = "Parent",Ent1 = ent,Ent2 = ent:GetParent()}) end
        local nophys = GetPlayerBool(ply,"parents_nophys")
        for k,v in pairs(ent:GetChildren()) do
            if not IsValid(v) then continue end
            if v:GetParent() ~= ent then continue end
            if not IsValid(v:GetPhysicsObject()) and not nophys then continue end
            numchild = numchild + 1
            table.insert(tbl,{Type = "Child",Ent1 = ent,Ent2 = v})
        end
    end
    ply.constraintmgr_selected = tbl -- Cache the constraints on the player for later (for removing constraints)
    return tbl,numconst,numchild
end
if SERVER then
    util.AddNetworkString("constraintmgr_notify")
    util.AddNetworkString("constraintmgr_tbl")
    util.AddNetworkString("constraintmgr_tbl_single")
    util.AddNetworkString("constraintmgr_remove")
    util.AddNetworkString("constraintmgr_clear")
    util.AddNetworkString("constraintmgr_active")
    util.AddNetworkString("constraintmgr_replace")
    Notify = function(ply,str)
        net.Start("constraintmgr_notify")
        net.WriteString(str)
        net.Send(ply)
    end
    SendTable = function(ply,tbl)
        net.Start("constraintmgr_tbl")
        net.WriteUInt(math.min(#tbl,255),8)
        for k, v in ipairs(tbl) do
            if not v.Type then continue end
            net.WriteUInt(k,8)
            net.WriteString(v.Type)
            local e = {v.Ent1,v.Ent2}
            local p = {v.LPos1,v.LPos2}
            if v.Type == "Ballsocket" then p = {vector_origin,v.LPos} end
            if v.Type == "Pulley" then p = {v.LPos1,v.LPos4} e = {v.Ent1,v.Ent4} end
            for l,b in ipairs(e) do
                net.WriteEntity(b)
                if not p[l] then net.WriteBool(false) continue end
                net.WriteBool(true)
                if b:IsWorld() then
                    net.WriteBool(false)
                    net.WriteFloat(p[l].x)
                    net.WriteFloat(p[l].y)
                    net.WriteFloat(p[l].z)
                else
                    net.WriteBool(true)
                    net.WriteVector(p[l])
                end
            end

            if k > 255 then break end
        end
        net.Send(ply)
    end
    SendTableSingle = function(ply,tbl)
        if tbl.Type ~= "Pulley" and tbl.LPos1 then
            tbl._curlength = tbl.Ent1:LocalToWorld(tbl.LPos1):Distance(tbl.Ent2:LocalToWorld(tbl.LPos2))
            --[[if not tbl.length and not tbl.Length1 then
                tbl.length = tbl._curlength
            end]]
        end
        if tbl.amplitude then tbl.Length2 = tbl.Length1 + tbl.amplitude end
        if tbl.addlength then tbl.length = tbl.length + tbl.addlength tbl.addlength = nil end
        if not tbl.color and tbl.material then tbl.color = color_white end
        for k,v in pairs(tbl) do -- Try to trim down unneccesary data
            if k == "Constraint" or string.find("Vector Angle",type(v)) then tbl[k] = tostring(v) end
            if k == "color" then tbl[k] = tostring(v.r) .. " " .. tostring(v.g) .. " " .. tostring(v.b) v = tbl[k] end
            if string.find("table function",type(v)) then tbl[k] = nil end
        end
        net.Start("constraintmgr_tbl_single")
        net.WriteUInt(table.Count(tbl),6)
        for k,v in pairs(tbl) do
            net.WriteString(k)
            net.WriteString(tostring(v))
        end
        net.WriteString("end")
        --net.WriteTable(tbl)
        net.Send(ply)
    end
    net.Receive("constraintmgr_tbl_single",function(_,ply)
        SendTableSingle(ply,CalcConstraints(ply,ply:GetTool("constraintmgr"):GetEnt(1))[net.ReadUInt(8)])
    end)
    net.Receive("constraintmgr_remove",function(_,ply)
        local c = net.ReadUInt(8)
        c = ply.constraintmgr_selected[c]
        if c then
            if c.Type == "Child" then
                c.Ent2:SetParent()
            elseif c.Type == "Parent" then
                c.Ent1:SetParent()
            else
                SafeRemoveEntity(c.Constraint)
            end
        end
        timer.Create("removed" .. ply:UserID(),0.1,1,function() -- Wait a bit in case it gets spammed
            SendTable(ply,CalcConstraints(ply,ply:GetTool("constraintmgr"):GetEnt(1)))
        end)
    end)
    net.Receive("constraintmgr_tbl",function(_,ply) -- Requested update from client
        SendTable(ply,CalcConstraints(ply,ply:GetTool("constraintmgr"):GetEnt(1)))
    end)
    net.Receive("constraintmgr_clear",function(_,ply)
        ply:GetTool("constraintmgr"):Holster()
    end)
    local function NewConstraint(t,n_u)
        local cAdvBallsocket = function(n) return constraint.AdvBallsocket(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.forcelimit,n.torquelimit,n.xmin,n.ymin,n.zmin,n.xmax,n.ymax,n.zmax,n.xfric,n.yfric,n.zfric,n.onlyrotation,n.nocollide) end
        local cAxis = function(n) return constraint.Axis(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.forcelimit,n.torquelimit,n.friction,n.nocollide,n.localaxis) end
        local cBallsocket = function(n) return constraint.Ballsocket(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos,n.forcelimit,n.torquelimit,n.nocollide) end
        local cElastic = function(n) return constraint.Elastic(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.constant,n.damping,n.rdamping,n.material,n.width,n.stretchonly,n.color) end
        local cKeepupright = function(n) return constraint.Keepupright(n.ent1,n.ang,n.bone,n.angularlimit) end
        local cHydraulic = function(n) return constraint.Hydraulic(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.length1,n.length2,n.width,n.key,n.fixed,n.speed,n.material,n.toggle,n.color) end
        local cMotor = function(n) return constraint.Motor(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.friction,n.torque,n.forcetime,n.nocollide,n.toggle,n.pl,n.forcelimit,n.numpadkey_fwd,n.numpadkey_bwd,n.direction,n.localaxis) end
        local cMuscle = function(n) return constraint.Muscle(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.length1,n.length2,n.width,n.key,n.fixed,n.period,n.amplitude,n.starton,n.material,n.color) end
        local cPulley = function(n) return constraint.Pulley(n.ent1,n.ent4,n.bone1,n.bone4,n.lpos1,n.lpos4,n.wpos2,n.wpos3,n.forcelimit,n.rigid,n.width,n.material,n.color) end
        local cRope = function(n) return constraint.Rope(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.length,n.addlength,n.forcelimit,n.width,n.material,n.rigid,n.color) end
        local cSlider = function(n) return constraint.Slider(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.width,n.material,n.color) end
        local cWeld = function(n) return constraint.Weld(n.ent1,n.ent2,n.bone1,n.bone2,n.forcelimit,n.nocollide,n.deleteent1onbreak) end
        local cWinch = function(n) return constraint.Winch(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.width,n.fwd_bind,n.bwd_bind,n.fwd_speed,n.bwd_speed,n.material,n.toggle,n.color) end
        local function UpdateWireConstraint(controller,const,const2) -- helper function to update wire constraint controllers
            const.MyCrtl = controller:EntIndex()

            controller:DontDeleteOnRemove(controller.constraint)
            controller.constraint:DontDeleteOnRemove(controller)
            if controller.const2 then controller:DontDeleteOnRemove(controller.const2) end

            controller:SetConstraint( const, const2 )
            controller:DeleteOnRemove( const )
            if const2 then controller:DeleteOnRemove( const2 ) end

            const:DeleteOnRemove( controller )
        end
        local cWireHydraulic = function(n)
            local const,rope = MakeWireHydraulic(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.width,n.material,n.speed,n.fixed,n.stretchonly)
            UpdateWireConstraint(Entity(n.mycrtl),const,rope)
            return const
        end
        local cWireMotor = function(n)
            local const,axis = MakeWireMotor(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.friction,n.torque,n.nocollide,n.forcelimit)
            UpdateWireConstraint(Entity(n.mycrtl),const,axis)
            return const
        end
        local funcs = {
            AdvBallsocket = cAdvBallsocket,
            Axis = cAxis,
            Ballsocket = cBallsocket,
            Elastic = cElastic,
            Hydraulic = cHydraulic,
            Keepupright = cKeepupright,
            Motor = cMotor,
            Muscle = cMuscle,
            Pulley = cPulley,
            Rope = cRope,
            Slider = cSlider,
            Weld = cWeld,
            Winch = cWinch,
            WireHydraulic = cWireHydraulic,
            WireMotor = cWireMotor
        }

        local c = false
        local n_l = {}
        for k,v in pairs(n_u) do n_l[string.lower(k)] = v end

        if n_l.length then n_l.length = math.max(n_l.length,0) end -- fix up odd values
        if n_l.addlength then n_l.length = n_l.length + n_l.addlength n_l.addlength = 0 end
        if n_l.fwd_speed then n_l.speed = n_l.fwd_speed end

        local world2 = n_l.ent2:IsWorld() and not n_l.ent1:IsWorld() -- swap ents/positions if ent2 is immovable
        local f_ent1, f_ent2 = n_l.ent1, n_l.ent2
        local f_lpos1, f_lpos2 = n_l.lpos1, n_l.lpos2
        if world2 then
            f_ent1, f_ent2 = n_l.ent2, n_l.ent1
            f_lpos1, f_lpos2 = n_l.lpos2, n_l.lpos1
        end

        local pos2 = n_l.ent2 and f_ent2:GetPos() or nil
        if n_l.length then -- maintain (or set) correct constraint length
            local wpos1,wpos2 = f_ent1:LocalToWorld(f_lpos1),f_ent2:LocalToWorld(f_lpos2)
            local gowpos2 = wpos2 - pos2
            f_ent2:SetPos(wpos1 - gowpos2 + Vector(n_l.length,0,0))
        end
        if funcs[t] then
            c = funcs[t](n_l)
        end
        if n_l.length then f_ent2:SetPos(pos2) end
        return c
    end
    local function ReadVecLong() return Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat()) end
    local read_types = {
        vec = ReadVecLong,
        ang = net.ReadAngle,
        col = net.ReadColor,
        flt = net.ReadFloat,
        int = net.ReadInt,
        boo = net.ReadBool,
        str = net.ReadString
    }
    local read_in = {
        int = 24,
        col = false
    }
    net.Receive("constraintmgr_replace",function(_,ply)
        local oldconst = constraint.GetTable(ply:GetTool("constraintmgr"):GetEnt(1))[net.ReadUInt(8)]
        local modified = {}
        local count = net.ReadUInt(6)
        for i = 1, count do
            local t,k = unpack(string.Split(net.ReadString(),","))
            if t == "end" then break end
            k = string.lower(k)
            local v = read_types[t](read_in[t])
            modified[k] = v
        end
        local c
        if table.Count(modified) > 0 then
            oldconst = table.LowerKeyNames(oldconst)
            local newconst = table.Merge(oldconst,modified)
            c = NewConstraint(oldconst.type,newconst)
            if c then
                c.result = 1
                c:CPPISetOwner(ply)
                undo.ReplaceEntity(oldconst.constraint,c)
                cleanup.ReplaceEntity(oldconst.constraint,c)
                SafeRemoveEntity(oldconst.constraint)
            else
                c = {result = 0}
            end
        else
            c = {result = 2}
        end
        net.Start("constraintmgr_replace") net.WriteUInt(c.result,2) net.Send(ply)
        if c.result ~= 1 then return end
        hook.Add("Tick","cmgr_replaceupdate",function()
            local t = ply:GetTool("constraintmgr")
            t:LeftClick({Entity = t:GetEnt(1)})
            hook.Remove("Tick","cmgr_replaceupdate")
        end)
    end)
end



function TOOL:LeftClick(trace)
    local ent = trace.Entity
    local ply = self:GetOwner()
    if not IsValid(ent) then
        if ent:IsWorld() then
            self:Clear()
        end
        return ent:IsWorld()
    end
    if ent:IsPlayer() then return false end
    if CLIENT then return true end
    if not IsValid(ent:GetPhysicsObject()) then return false end
    self:SetObject(1,ent,vector_origin,ent:GetPhysicsObject(),0,vector_origin)
    local ctbl,con,chi = CalcConstraints(ply,ent)
    Notify(ply,tostring(ent) .. " has " .. tostring(con) .. (con == 1 and " constraint" or " constraints") .. (chi > 0 and " and " .. tostring(chi) .. " child" .. (chi == 1 and "" or "ren") or ""))
    if #ctbl == 0 then
        self:Clear()
        return true
    end
    SendTable(ply,ctbl)
    hook.Add("PreUndo","constraintmgr_undo_" .. ply:UserID(),function(tbl)
        if not tbl then return end
        if tbl.Owner ~= ply then return end
        local send
        for k,v in ipairs(tbl.Entities) do
            if not IsValid(v) or v:IsConstraint() or v.Type then
                send = true
                break
            end
        end
        if send then
            timer.Create("undo_" .. ply:UserID(),0.1,1,function() SendTable(tbl.Owner,CalcConstraints(ply,ent)) end)
        end
    end)
    return true
end

function TOOL:RightClick(trace)
    self:Clear()
    return true
end
function TOOL:Deploy()
    if SERVER then -- fix for Deploy not getting called on client when switching tools
        net.Start("constraintmgr_active") net.WriteBool(true) net.Send(self:GetOwner())
        return
    end
    toolactive = true
    tool = self
    hook.Add("Think","constraintmgr_think",Think)
    hook.Add("HUDPaint","constraintmgr_renderhud",HUDPaint)
    hook.Add("PreDrawEffects","constraintmgr_render3d",PreDrawEffects)
    hook.Add("PlayerBindPress","constraintmgr_bind",PlayerBindPress)
    hook.Add("KeyPress","constraintmgr_keypress",KeyPress)
    hook.Add("KeyRelease","constraintmgr_keyrelease",KeyRelease)
end
function TOOL:Holster()
    if SERVER then -- fix for Holster not getting called on client when switching tools
        net.Start("constraintmgr_active") net.WriteBool(false) net.Send(self:GetOwner())
    end
    if CLIENT then
        toolactive = false
        hook.Remove("PlayerBindPress","constraintmgr_bind")
        hook.Remove("KeyPress","constraintmgr_keypress")
        hook.Remove("KeyRelease","constraintmgr_keyrelease")
    end
    if self:GetClientBool("persist") then return end
    if CLIENT then
        hook.Remove("Think","constraintmgr_think")
        hook.Remove("HUDPaint","constraintmgr_renderhud")
        hook.Remove("PreDrawEffects","constraintmgr_render3d")
    end
    self:Clear()
end
function TOOL:Reload(data)
    if SERVER then return IsValid(self:GetEnt(1)) and true or false end
end