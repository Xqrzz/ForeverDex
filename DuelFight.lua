local _, ns = ...
local Fight = {}
ns.DuelFight = Fight

function Fight.New(round)
    return { phase = "pick", round = round }
end

function Fight.Pick(fight, entry)
    if fight.phase ~= "pick" or not entry then return end
    fight.phase, fight.mine = "wait", entry
    return true
end

function Fight.Ready(fight)
    if fight.phase ~= "pick" and fight.phase ~= "wait" then return end
    fight.theirReady = true
    return true
end

function Fight.ReceiveCard(fight, entry)
    if not entry or fight.theirs or not Fight.Ready(fight) then return end
    fight.theirs = entry
    return true
end

function Fight.CardToSend(fight)
    if not fight.mine or not fight.theirReady or fight.sent then return end
    fight.sent = true
    return fight.mine
end

function Fight.Reveal(fight)
    if fight.phase ~= "wait" or not fight.theirs then return end
    fight.phase, fight.deadline = "reveal", nil
    return true
end

function Fight.OpenVote(fight)
    if fight.phase ~= "reveal" then return end
    fight.phase = "vote"
    return true
end

function Fight.Vote(fight, choice, remote)
    if choice ~= "O" and choice ~= "T" then return end
    local field = remote and "theirVote" or "myVote"
    if fight[field] then return end
    if fight.phase ~= "vote" and not (remote and fight.phase == "reveal") then return end
    fight[field] = choice
    return true
end

function Fight.Resolve(fight)
    if fight.phase ~= "vote" or not fight.myVote or not fight.theirVote then return end
    fight.phase, fight.deadline = "result", nil
    return true
end
