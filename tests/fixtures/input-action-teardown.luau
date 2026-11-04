--!strict

return [==[
local input=game.UserInputService
for _,destroyContext in {false,true} do
 local context=Instance.new("InputContext")
 context.Parent=game.Players.LocalPlayer.PlayerGui
 local action=Instance.new("InputAction")
 action.Parent=context
 local binding=Instance.new("InputBinding")
 binding.KeyCode=if input.PreferredInput==Enum.PreferredInput.Gamepad then Enum.KeyCode.ButtonX else Enum.KeyCode.H
 binding.Parent=action
 task.wait(.05)
 assert(action.PreferredBinding==binding,"binding matches the current device")
 local changed=0
 local connection=action:GetPropertyChangedSignal("PreferredBinding"):Connect(function() changed+=1 end)
 binding.Parent=nil
 task.wait(.05)
 assert(action.PreferredBinding==nil and changed==1,"unparenting a live binding notifies")
 binding.Parent=action
 task.wait(.05)
 assert(action.PreferredBinding==binding and changed==2,"reparenting a live binding notifies")
 if destroyContext then context:Destroy() else action:Destroy() end
 task.wait(.05)
 assert(changed==2,"destruction does not notify a disposed binding observer")
 assert(action.PreferredBinding==binding,"destruction retains the last binding")
 connection:Disconnect()
 context:Destroy()
end
return true
]==]
