--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.Parent = game:GetService("Players").LocalPlayer.PlayerGui
local ok, failure = pcall(function()
    local frame = Instance.new("Frame")
    frame:AddTag("Card")
    frame:AddTag("Hot")
    frame.Parent = screen
    local text = Instance.new("TextLabel")
    text:AddTag("Card")
    text.Parent = screen
    local sheet = Instance.new("StyleSheet")
    sheet.Parent = screen
    local link = Instance.new("StyleLink")
    link.StyleSheet, link.Parent = sheet, screen
    local corner = Instance.new("StyleRule")
    corner.Selector = ".Card::UICorner"
    corner:SetProperties({CornerRadius = UDim.new(0, 12)})
    corner.Parent = sheet
    local rule = Instance.new("StyleRule")
    rule.Priority = 10
    rule:SetProperties({BackgroundTransparency = 0.65})
    rule.Parent = sheet
    local function verify(selector, expectedFrame, expectedText)
        rule.Selector = selector
        task.wait(0.05)
        assert(math.abs(frame:GetStyled("BackgroundTransparency") - expectedFrame) < 0.00001, selector .. " frame")
        assert(math.abs(text:GetStyled("BackgroundTransparency") - expectedText) < 0.00001, selector .. " text")
        assert(#frame:GetChildren() == 0, "pseudo-instance changes the physical hierarchy")
    end
    verify("Frame.Card", 0.65, 0)
    verify("GuiObject.Card", 0.65, 0.65)
    verify(".Card.Hot", 0.65, 0)
    verify("Frame.Card.Hot", 0.65, 0)
    verify("Frame.Hot.Card", 0.65, 0)
    verify("Frame.Card.Missing", 0, 0)
    verify("TextLabel.Card, Frame.Hot", 0.65, 0.65)
    frame:RemoveTag("Hot")
    verify("Frame.Card.Hot", 0, 0)
    frame:AddTag("Hot")
    verify("Frame.Card.Hot", 0.65, 0)
end)
screen:Destroy()
assert(ok, failure)
return true
]==]
