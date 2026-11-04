--!strict

local Test = require "./harness"
local it = Test.it

local probe = require "./fixtures/ui-scrolling-flex"

local run = require "./scaled-padding-run"
it("flex items in a padded ScrollingFrame grow over the unpadded width as Studio 0.744 does", run(probe))

return nil
