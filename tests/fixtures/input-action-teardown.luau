--!strict

return [==[
local input=game.UserInputService
local detached=Instance.new("InputContext")
local detachedAction=Instance.new("InputAction")
detachedAction.Parent=detached
local detachedBinding=Instance.new("InputBinding")
detachedBinding.KeyCode,detachedBinding.Parent=Enum.KeyCode.K,detachedAction
task.wait(.05)
assert(detachedAction.PreferredBinding==nil,"unparented actions have no preferred binding")
detached.Parent=game.Players.LocalPlayer.PlayerGui
task.wait(.05)
local previous=detachedAction.PreferredBinding
local notifications=0
local detachedConnection=detachedAction:GetPropertyChangedSignal("PreferredBinding"):Connect(function() notifications+=1 end)
detached.Parent=nil
task.wait(.05)
assert(detachedAction.PreferredBinding==previous and notifications==0,"detached actions retain their last binding without notifications")
detachedConnection:Disconnect()
detached:Destroy()
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
