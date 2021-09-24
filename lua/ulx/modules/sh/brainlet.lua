local opentdb = TASUtils.OpenTDB
if not opentdb then error("ULX loads modules before TASUtils") end
local brainlet = function() end

if SERVER then
	util.AddNetworkString("TASUtils.Brainlet")
	local questionTime = CreateConVar("brainlet_time", 30, FCVAR_ARCHIVE, "Number of seconds users get to answer a question", 1)
	local outstandingBrainlets = {}

	-- Invalidate and apply brainlets
	hook.Add("Think", "TASUtils.Brainlet", function()
		local curtime = CurTime()
		for plr, question in pairs(outstandingBrainlets) do
			if not IsValid(plr) then -- If the player is invalid remove their brainlet
				outstandingBrainlets[plr] = nil
			elseif curtime >= question.deadline then -- They've failed to answer the brainlet in time
				outstandingBrainlets[plr] = nil
				TASUtils.Broadcast(team.GetColor(plr:Team()), plr:Nick(), Color(255, 255, 255), " failed to answer the brainlet in time")
				ULib.kick(plr, "You are officially a dumbass")
			end
		end
	end)

	net.Receive("TASUtils.Brainlet", function(_, plr)
		if not outstandingBrainlets[plr] then return end

		local answer = net.ReadString()
		if answer == outstandingBrainlets[plr].answer then
			TASUtils.Broadcast(team.GetColor(plr:Team()), plr:Nick(), Color(255, 255, 255), " correctly answered the brainlet!")
		else
			TASUtils.Broadcast(
				team.GetColor(plr:Team()), plr:Nick(),
				Color(255, 255, 255), " incorrectly answered the brainlet \"",
				Color(240, 224, 86), outstandingBrainlets[plr].question,
				Color(255, 255, 255), "\", the right answer was \"",
				Color(77, 255, 80), outstandingBrainlets[plr].answer,
				Color(255, 255, 255), "\", but they answered \"",
				Color(255, 91, 77), answer,
				Color(255, 255, 255), "\""
			)
			ULib.kick(plr, "You are officially a dumbass")
		end

		outstandingBrainlets[plr] = nil
	end)

	brainlet = function(caller, target, category, difficulty)
		if CLIENT then return end -- Seems ULX commands only run serverside, but just incase

		if outstandingBrainlets[target] then
			caller:ChatPrint("That player is already being brainlet'd")
			return
		end

		-- Fetch question from trivia API/dataset
		opentdb.FetchQuestions(function(success, questions)
			-- Check the request was successful
			if not success or #questions == 0 then
				caller:ChatPrint("Failed to get a question from the OpenTDB API")
				return
			end

			local question = questions[1]
			local deadline = CurTime() + questionTime:GetFloat()

			-- Register brainlet (tracked serverside so without svlua there's literally no way to bypass, unlike a certain server's brainlet :trollhd:)
			outstandingBrainlets[target] = {
				answer = question.correct_answer,
				deadline = deadline
			}

			-- Send question to target client to be answered
			-- Packet schema:
			-- category               : string
			-- difficulty             : string
			-- question               : string
			-- multipleChoice         : bool
			-- if multipleChoice:
			--     correctAnswer      : string
			--     numIncorrectAnswers: uint8
			--     incorrectAnswers   : string[numIncorrectAnswers]
			-- else
			--     correctAnswer      : bool
			-- deadline               : float
			net.Start("TASUtils.Brainlet")
				net.WriteString(question.category)
				net.WriteString(question.difficulty)
				net.WriteString(question.question)

				if question.type == "multiple" then
					net.WriteBool(true)
					net.WriteString(question.correct_answer)

					local numIncorrectAnswers = #question.incorrect_answers
					net.WriteUInt(numIncorrectAnswers, 8)
					for i = 1, numIncorrectAnswers do
						net.WriteString(question.incorrect_answers[i])
					end
				else
					net.WriteBool(false)
					net.WriteBool(question.correct_answer == "True")
				end

				net.WriteFloat(deadline) -- Note this isn't used for validation, just the timer GUI
			net.Send(target)

			-- Log that a brainlet was initiated
			ulx.fancyLogAdmin(caller, "#A is testing if #T is a brainlet", target)
		end, 1, opentdb.Category[category], opentdb.Difficulty[difficulty])
	end
else
	net.Receive("TASUtils.Brainlet", function()
		-- Read packet
		local category = net.ReadString()
		local difficulty = net.ReadString()
		local question = net.ReadString()

		local correctAnswer, answers = nil, {}
		if net.ReadBool() then -- Multiple choice
			for i = 1, net.ReadUInt(8) do
				answers[i] = net.ReadString()
			end
			answers[#answers + 1] = correctAnswer
			TASUtils.ShuffleTable(answers) -- Shuffle the table so the correct answer is always in a random position
		else -- True/False
			correctAnswer = net.ReadBool()
			answers = {"True", "False"}
		end

		local deadline = net.ReadFloat()

		-- Create the GUI window for brainlet (for testing this can literally just be a plain derma window)
	end)
end

-- Register CMD
local cmd = ulx.command("TAS Utilities", "ulx brainlet", brainlet, "!brainlet")

cmd:addParam({type = ULib.cmds.PlayerArg, hint = "Player to brainlet"})
cmd:addParam({
	type = ULib.cmds.StringArg,
	hint = "Question category (defaults to GeneralKnowledge)",
	error = "Invalid category \"%s\"",
	completes = table.GetKeys(opentdb.Category),

	-- Flags
	ULib.cmds.optional, ULib.cmds.restrictToCompletes
})
cmd:addParam({
	type = ULib.cmds.StringArg,
	hint = "Question difficulty (defaults to Easy)",
	error = "Invalid difficulty \"%s\"",
	completes = table.GetKeys(opentdb.Difficulty),
	
	-- Flags
	ULib.cmds.optional, ULib.cmds.restrictToCompletes
})

cmd:defaultAccess(ULib.ACCESS_OPERATOR)
cmd:help("Makes a player have to answer a simple trivia question to not get kicked")