TOOL.Category = "Constraints"
TOOL.Name = "#tool.constraintmgr.name"

TOOL.ClientConVar["persist"] = 0
TOOL.ClientConVar["cam_nolabels"] = 1
TOOL.ClientConVar["parents"] = 1
TOOL.ClientConVar["sound"] = 1
TOOL.ClientConVar["cull"] = 1
TOOL.ClientConVar["overlap"] = 0
TOOL.ClientConVar["parents_nophys"] = 0
TOOL.ClientConVar["scale_line"] = 1

local toolactive = false
local tool

if CLIENT then
    TOOL.Information = {
        {name = "left_0", stage = 0},
        {name = "left_1", stage = 1},
        {name = "right"},
        {name = "reload", stage = 1},
        {name = "alt",icon = "icon16/control_pause.png"}
    }
    local t = "tool.constraintmgr."
    language.Add(t.."name","Constraint Manager")
    language.Add(t.."desc","View and modify constraints")
    language.Add(t.."left_0","Select entity")
    language.Add(t.."left_1","Inspect constraint")
    language.Add(t.."right","Clear entity")
    language.Add(t.."reload","Remove highlighted constraint")
    language.Add(t.."alt","Alt: Freeze display")

    language.Add(t.."var.persist","Keep constraints visible when switching tools")
    language.Add(t.."var.cam_nolabels","Hide tooltips while using the camera")
    language.Add(t.."var.parents","Show parent/child relations as constraints")
    language.Add(t.."var.parents_nophys","Show children without physics")
    language.Add(t.."var.sound","Enable tool sounds")
    language.Add(t.."var.cull","Hide constraints far from crosshair")
    language.Add(t.."var.overlap","Performance: Allow tooltip overlap")
    language.Add(t.."var.scale_line","Line scale")

    function TOOL.BuildCPanel(panel)
        t = "#"..t
        local c
        local checkcam
        panel:CheckBox(t.."var.persist","constraintmgr_persist").OnChange = function(_,val)
            checkcam:SetEnabled(val)
            if not tool then return end
            if not val and not toolactive then
                timer.Create("wait_persist",0.02,1,function()
                    net.Start("constraintmgr_clear")
                    net.SendToServer()
                    tool:Holster()
                end)
            end
        end
        checkcam = panel:CheckBox(t.."var.cam_nolabels","constraintmgr_cam_nolabels")
        checkcam:SetTooltip("Great for screenshots!")

        c = vgui.Create("DPanel",panel) c:SetHeight(1) panel:AddItem(c)

        local checkno
        c = panel:CheckBox(t.."var.parents","constraintmgr_parents")
        c.OnChange = function(_,val)
            timer.Create("wait_parent",0.02,1,function()
                checkno:SetEnabled(val)
                net.Start("constraintmgr_tbl")
                net.SendToServer()
            end)
        end
        c:SetTooltip("Constraint info is unavailable for these,\nas they do not represent real constraints.")
        checkno = panel:CheckBox(t.."var.parents_nophys","constraintmgr_parents_nophys")
        checkno.OnChange = function(_,val)
            timer.Create("wait_parent",0.02,1,function()
                net.Start("constraintmgr_tbl")
                net.SendToServer()
            end)
        end
        checkno:SetTooltip("Holograms, etc.")

        c = vgui.Create("DPanel",panel) c:SetHeight(1) panel:AddItem(c)

        panel:CheckBox(t.."var.cull","constraintmgr_cull")
        panel:CheckBox(t.."var.sound","constraintmgr_sound")
        panel:CheckBox(t.."var.overlap","constraintmgr_overlap"):SetTooltip("Checking this may improve FPS in extreme cases!")
        panel:NumSlider(t.."var.scale_line","constraintmgr_scale_line",0,3,1):SetTooltip("Only thin lines will be rendered if set to 0.")
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
        Slider = Color(100,50,200)
    }
    local textcol = {}
    local textwidth = {}

    local scr = {x=0,y=0}
    local cur = {x=0,y=0}
    local col = {
        grey = Color(150,150,150,100),
        black = Color(0,0,0),
        hover_bg = Color(50,255,50,200),
        black_half = Color(0,0,0,150),
        black_220 = Color(0,0,0,220),
        selected0 = Color(255,0,0),
        selected1 = Color(255,255,255),
        green = Color(0,255,0)
    }
    local hovered,selected,selection = nil,nil,0
    local lasthover = nil
    local freeze = false

    local function InitType(str) -- Initial setup for constraint visuals
        if textwidth[str] then return end
        linecol[str] = linecol[str] or Color(255,0,200)
        local col = {ColorToHSV(linecol[str])}
        textcol[str] = HSVToColor(col[1],col[2]*0.5,(col[3]+1)*0.5)

        local width = 0
        for c in str:gmatch(".") do
            width = width + ((string.find(c,"[ .Iijl]",1) == nil) and 1 or 0.5)
            width = width + ((string.find(c,"[A-Zdp]",1) == nil) and 0 or 0.25)
            width = width + ((string.find(c,"[Ww]",1) == nil) and 0 or 0.55)
        end
        textwidth[str] = width
    end

    for k in pairs(linecol) do InitType(k) end

    local constraints = {}
    local constraintGroups = {}
    local function GroupConstraints() -- Sort constraints into tables if they share the same entities and positions
        hovered, selected, selection = nil,nil,1
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
            v = g[1]
            v.size = {x = 10 + v.widest*9, y = 8 + #g*15}
        end
    end

    net.Receive("constraintmgr_tbl",function() -- List of constraints from server
        local n = net.ReadUInt(8)
        local tbl = {}
        target = net.ReadEntity()
        for i = 1,n do
            local id = net.ReadUInt(8)
            tbl[id] = {Index = id}
            tbl[id].Type = net.ReadString()
            --tbl[id].Type = "Wewew"
            InitType(tbl[id].Type)
            for j=1,2 do
                tbl[id]["Ent"..tostring(j)] = net.ReadEntity()
                if not net.ReadBool() then
                    tbl[id].LPos1 = Vector()
                    tbl[id].LPos2 = Vector()
                    continue
                end
                local idx = "LPos"..tostring(j)
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
        --PrintTable(tbl)
        GroupConstraints()
    end)

    local function IsValidW(ent)
        if ent == game.GetWorld() then return true end
        return IsValid(ent)
    end

    function TOOL:SetStage(stage) timer.Create("setstage",0.02,1,function() self._stage = stage end) end
    function TOOL:GetStage() return self._stage or 0 end -- Override clientside Stage functions (they do nothing)

    hook.Add("Think","constraintmgr_think",function() -- Calculating constraint worldpos and relative tooltip positions
        if #constraints == 0 then return end
        for k,g in ipairs(constraintGroups) do
            if not freeze or not v.WPos1 then
                for l,v in ipairs(g) do
                    if not IsValidW(v.Ent1) or not IsValidW(v.Ent2) then table.remove(constraints,k) break end
                    v.WPos1 = (v.Ent1:IsWorld() and v.LPos1 == Vector()) and (v.Ent2:GetPos() + Vector(0,0,-32)) or v.Ent1:LocalToWorld(v.LPos1)
                    v.WPos2 = (v.Ent2:IsWorld() and v.LPos2 == Vector()) and (v.Ent1:GetPos() + Vector(0,0,-32)) or v.Ent2:LocalToWorld(v.LPos2)
                end
            end
            v = g[1]
            if not v then break end
            if (not freeze or not v.WPos) and v.WPos1 then
                v.WPos = ((v.WPos1 + v.WPos2)*0.5)
                v.Length = v.WPos1:Distance(v.WPos2)
                for l,b in ipairs(g) do
                    b.WPos = v.WPos
                end
            end
            v.mins = v.mid and {x=v.mid.x-v.size.x*0.5,y=v.mid.y-v.size.y*0.5} or {x=9999,y=9999}
            v.maxs = {x = v.mins.x + v.size.x, y = v.mins.y + v.size.y}
            if tool:GetClientBool("overlap") then continue end -- Skip overlap checking
            v.movedr = 0
            v.movedl = 0
            for i = 1,#constraintGroups*0.5 do
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
    end)
    local function DrawBeam(pos1,pos2,c,scale,thin)
        scale = scale*tool:GetClientNumber("scale_line",0)
        if scale > 0 then
            render.SetColorMaterialIgnoreZ()
            render.StartBeam(2)
            render.AddBeam(pos1,0.3*scale,0,c)
            render.AddBeam(pos2,1*scale,0,c)
            render.EndBeam()
        end
        if thin then render.DrawLine(pos1,pos2,c) end
    end
    local function CalcScale(l) return l and (0.1 + ((math.min(l,512)*1)^0.8)*0.01) or 1 end
    hook.Add("PreDrawEffects","constraintmgr_render3d",function() -- Render lines/beams
        if #constraints == 0 then return end
        local scale = 1
        for k,v in ipairs(constraintGroups) do
            local n = #v
            scale = CalcScale(v[1].Length)
            for l,b in ipairs(v) do
                if not b.WPos1 then continue end
                DrawBeam(b.WPos1,b.WPos2,linecol[b.Type],scale*(1+(n-l)*2),l==1)
            end
        end
        if hovered then
            local sel = constraintGroups[hovered][selection]
            local v = constraintGroups[hovered][1]
            scale = CalcScale(v.Length)
            DrawBeam(sel.WPos1,sel.WPos2,(CurTime()%1 < 0.5) and col.selected0 or col.selected1,scale*(1+(#constraintGroups[hovered]-selection)*2),true)
        end
    end)
    local scr,cur,center = Vector(),Vector(),Vector()
    hook.Add("HUDPaint","constraintmgr_renderhud",function() -- Render tooltips
        if #constraints == 0 then
            if lasthover then
                tool:SetStage(0)
                lasthover = nil
            end
            return
        end
        if tool:GetClientBool("cam_nolabels") and LocalPlayer():GetActiveWeapon():GetClass() == "gmod_camera" then return end

        scr.x = ScrW() scr.y = ScrH()
        cur.x = ScrW()*0.5 cur.y = ScrH()*0.5
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
            if toolactive then
                if cur.x > v.mins.x and cur.x < v.maxs.x and cur.y > v.mins.y and cur.y < v.maxs.y then
                    hovered = k
                end
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
            --mins.x = math.floor(mins.x)
            --mins.y = math.floor(mins.y)
            local size = v[1].size
            v[1].render = true
            if tool:GetClientBool("cull") then
                local s = v[1].WPos:ToScreen()
                center.x = s.x--mins.x + size.x*0.5
                center.y = s.y--mins.y + size.y*0.5
                if center:Distance2D(cur) > scr.y*0.25 then v[1].render = false continue end
            end
            draw.RoundedBox(0,mins.x,mins.y,size.x,size.y,(hovered == k) and col.hover_bg or col.grey)
            draw.RoundedBox(0,mins.x+2,mins.y+2,size.x - 4,size.y - 4,(hovered == k) and col.black_220 or col.black_half)
            for l,b in ipairs(v) do
                local c = (selection == l and hovered == k) and ((CurTime()%1 < 0.5) and col.selected0 or col.selected1) or textcol[b.Type]
                --[[draw.TextShadow(
                    {text=b.Type,font="TargetID",pos={mins.x+4,mins.y + l*15 - 16},xalign=TEXT_ALIGN_LEFT,yalign=TEXT_ALIGN_TOP,color=col.black},
                    1,255
                )]]
                draw.SimpleTextOutlined(b.Type,"ChatFont",mins.x + 4,mins.y + l*15 - 14,c,TEXT_ALIGN_LEFT,TEXT_ALIGN_TOP,1,col.black_half)
            end
        end
    end)
    local window
    local function Inspect(id) -- Popup window with constraint info
        const = constraints[id]
        if not const then return end
        if const.Type == "Parent" or const.Type == "Child" then return end
        if IsValid(window) then
            window:Remove()
        end
        window = vgui.Create("DFrame")
        window.OnRemove = function() hook.Remove("PreDrawHalos","constraintmgr_model_halo") end
        local sw = ScrW()
        local sh = ScrH()
        window:SetSize(280 + sw*0.08,360 + sh*0.2) -- 480p-friendly! :)
        window:SetSizable(true)
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
        net.Start("constraintmgr_tbl_single") net.WriteUInt(id,8) net.SendToServer()
        local ReturnTrue = function() return true end
        net.Receive("constraintmgr_tbl_single",function()
            local tbl = net.ReadTable()
            window:SetTitle("Constraint info for "..const.Type.." ["..tostring(id).."]")
            local copied
            for k,v in SortedPairs(tbl) do
                if type(v) == "table" then continue end

                items[k] = panel:Add("EditablePanel")
                items[k]:SetHeight(20)
                items[k]:DockMargin(4,4,4,-2)
                items[k]:Dock(TOP)

                items[k].label = items[k]:Add("DLabel")
                items[k].label:SetText(k.." = ")
                items[k].label:SetColor(fg)
                items[k].label:SetWidth(100 + sw*0.01)
                items[k].label:Dock(LEFT)

                items[k].entry = items[k]:Add("DTextEntry")
                items[k].entry:SetText(tostring(v))
                items[k].entry:SetWidth(215 + sw*0.012)
                items[k].entry.AllowInput = ReturnTrue
                items[k].entry:Dock(RIGHT)
                if type(v) == "Entity" and IsValid(v) then -- Icon for props
                    local model = v:GetModel() or ""
                    if util.IsValidProp(model) then
                        items[k].icon = items[k].entry:Add("SpawnIcon")
                        items[k].icon:SetModel(model)
                        items[k].icon:SetWidth(33)
                        items[k].icon:DockMargin(0,0,1,0)
                        items[k].icon:Dock(RIGHT)
                        items[k].icon:SetTooltip("[Click to copy] "..model)
                        items[k].icon._itemindex = k
                        items[k].icon.DragMousePress = function(self,code) -- Copy model to clipboard
                            if code ~= MOUSE_LEFT then return end
                            SetClipboardText(model)
                            if copied then copied:Remove() end
                            copied = self:Add("DPanelOverlay")
                            copied:SetColor(col.green)
                            if tool:GetClientBool("sound") then LocalPlayer():EmitSound("buttons/button14.wav",nil,120,0.3) end
                        end
                    end
                end
                if k == "material" then -- Icon for rope material
                    items[k].icon = items[k].entry:Add("DImage")
                    items[k].icon:SetMaterial(v)
                    items[k].icon:SetWidth(16)
                    items[k].icon:DockMargin(0,0,2,0)
                    items[k].icon:Dock(RIGHT)
                end
                if k == "Constraint" then
                    items[k].entry:SetTooltip("[Serverside entity]")
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
    hook.Add("PlayerBindPress","constraintmgr_bind",function(ply,bind,pressed) -- Detect clicks/scrolls
        if IsFirstTimePredicted() then return end -- Seems to break stuff if you check for (not IsFirstTimePredicted())
        if not toolactive then return end
        if not pressed then return end
        if not hovered then return end
        if bind == "+attack" then
            if #constraintGroups[hovered] == 1 or selection == 0 then
                selection = 1
            end
            if tool:GetClientBool("sound") then
                local t = constraintGroups[hovered][selection].Type
                LocalPlayer():EmitSound((t == "Parent" or t == "Child") and "buttons/lightswitch2.wav" or "buttons/button9.wav",nil,100,0.5)
            end
            Inspect(constraintGroups[hovered][selection].Index)
            return true
        end
        local scroll
        if bind == "invnext" then scroll = 1 elseif bind == "invprev" then scroll = -1 end
        if scroll then
            if tool:GetClientBool("sound") then LocalPlayer():EmitSound("weapons/pistol/pistol_empty.wav",nil,120,0.3) end
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
            --tool:Reload({success = true})
            return false
        end
    end)
    hook.Add("KeyPress","constraintmgr_keypress",function(ply,key)
        if not toolactive then return end
        if key == IN_WALK then freeze = true end
    end)
    hook.Add("KeyRelease","constraintmgr_keyrelease",function(ply,key)
        if not toolactive then return end
        if key == IN_WALK then freeze = false end
    end)
end

local target
local constraints = {}
local Notify,SendTable,SendTableSingle
function TOOL:Clear()
    self:ClearObjects()
    if CLIENT then return end
    SendTable(self:GetOwner(),{})
    target = nil
    hook.Remove("constraintmgr_undo")
end
function TOOL:CalcConstraints(ent) -- Get table of constraints, and include parent/child relations
    if not IsValid(ent) then self:Clear() return {},0,0 end
    local tbl = constraint.GetTable(ent)
    local numconst = #tbl
    local numchild = 0
    if self:GetClientBool("parents") then
        if IsValid(ent:GetParent()) then table.insert(tbl,{Type = "Parent",Ent1 = ent,Ent2 = ent:GetParent()}) end
        for k,v in pairs(ent:GetChildren()) do
            if not IsValid(v) then continue end
            if v:GetParent() ~= ent then continue end
            if not IsValid(v:GetPhysicsObject()) and not self:GetClientBool("parents_nophys") then continue end
            numchild = numchild + 1
            table.insert(tbl,{Type = "Child",Ent1 = ent,Ent2 = v})
        end
    end
    constraints = tbl
    return tbl,numconst,numchild
end
if SERVER then
    util.AddNetworkString("constraintmgr_notify")
    util.AddNetworkString("constraintmgr_tbl")
    util.AddNetworkString("constraintmgr_tbl_single")
    util.AddNetworkString("constraintmgr_remove")
    util.AddNetworkString("constraintmgr_clear")
    Notify = function(ply,str)
        net.Start("constraintmgr_notify")
        net.WriteString(str)
        net.Send(ply)
    end
    SendTable = function(ply,tbl)
        net.Start("constraintmgr_tbl")
        net.WriteUInt(math.min(#tbl,255),8)
        net.WriteEntity(target)
        for k, v in ipairs(tbl) do
            if not v.Type then continue end
            net.WriteUInt(k,8)
            net.WriteString(v.Type)
            local e = {v.Ent1,v.Ent2}
            local p = {v.LPos1,v.LPos2}
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
        net.Start("constraintmgr_tbl_single")
        for k,v in pairs(tbl) do -- Try to trim down unneccesary data
            if type(v) == "table" or type(v) == "function" then tbl[k] = nil end
            if k == "Constraint" or type(v) == "Vector" or type(v) == "Angle" then tbl[k] = tostring(v) end
        end
        net.WriteTable(tbl)
        net.Send(ply)
    end
    net.Receive("constraintmgr_tbl_single",function(_,ply)
        SendTableSingle(ply,constraint.GetTable(target)[net.ReadUInt(8)])
    end)
    net.Receive("constraintmgr_remove",function(_,ply)
        local c = net.ReadUInt(8)
        c = constraints[c]
        if c then
            if c.Type == "Child" then
                c.Ent2:SetParent()
            elseif c.Type == "Parent" then
                c.Ent1:SetParent()
            else
                SafeRemoveEntity(c.Constraint)
            end
        end
        timer.Create("removed",0.1,1,function() -- Wait a bit in case it gets spammed
            SendTable(ply,tool:CalcConstraints(target))
        end)
    end)
    net.Receive("constraintmgr_tbl",function(_,ply) -- Requested update from client
        if not tool then return end
        SendTable(ply,tool:CalcConstraints(target))
    end)
    net.Receive("constraintmgr_clear",function(_,ply)
        tool:Holster()
    end)
end



function TOOL:LeftClick(trace)
    toolactive = true
    local ent = trace.Entity
    if not IsValid(ent) then
        if ent:IsWorld() then
            self:Clear()
        end
        return ent:IsWorld()
    end
    if ent:IsPlayer() then return false end
    if CLIENT then return true end
    if not IsValid(ent:GetPhysicsObject()) then return false end
    target = ent
    local tbl,con,chi = self:CalcConstraints(ent)
    Notify(self:GetOwner(),tostring(ent).." has "..tostring(con).." constraints"..(chi > 0 and " and "..tostring(chi).." child"..(chi == 1 and "" or "ren") or ""))
    if #tbl == 0 then
        self:Clear()
        return true
    end
    SendTable(self:GetOwner(),tbl)
    hook.Add("PreUndo","constraintmgr_undo",function(tbl)
        if not tbl then return end
        for k,v in ipairs(tbl.Entities) do
            if not IsValid(v) or v:IsConstraint() or v.Type then
                timer.Create("constraintmgr_undo",0.1,1,function()
                    SendTable(tbl.Owner,self:CalcConstraints(ent))
                end)
            end
        end
    end)
    return true
end

function TOOL:RightClick(trace)
    self:Clear()
    return true
end
function TOOL:Deploy() toolactive = true tool = self end
function TOOL:Holster()
    toolactive = false
    if self:GetClientBool("persist") then return end
    self:Clear()
end
function TOOL:Reload(data)
    if SERVER then return target and true or false end
    --if data.success then return true end
end