love.physics.setMeter(64)


MAIN_RELIABLE_CHANNEL = 0

PHYSICS_RELIABLE_CHANNEL = 100
PHYSICS_SERVER_SYNCS_CHANNEL = 101
PHYSICS_CLIENT_SYNCS_CHANNEL = 102

TOUCHES_CHANNEL = 50


-- Define

function GameCommon:define()
    --
    -- User
    --

    -- Server sends full state to a new client when it connects
    self:defineMessageKind('fullState', {
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = false,
    })

    -- Client sends user profile info when it connects, forwarded to all and self
    self:defineMessageKind('me', {
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = true,
        forward = true,
    })

    --
    -- Physics
    --

    local function definePhysicsConstructors(methodNames) -- For `love.physics.new<X>`, first arg is new `physicsId`
        for _, methodName in ipairs(methodNames) do
            local kind = 'physics_' .. methodName

            self:defineMessageKind(kind, {
                from = 'server',
                to = 'all',
                reliable = true,
                channel = PHYSICS_RELIABLE_CHANNEL,
                selfSend = true,
                forward = true,
            })

            if not GameCommon.receivers[kind] then
                GameCommon.receivers[kind] = function(self, time, physicsId, ...)
                    (function (...)
                        local obj = love.physics[methodName](...)
                        self.physicsIdToObject[physicsId] = obj
                        self.physicsObjectToId[obj] = physicsId
                    end)(self:physics_resolveIds(...))
                end

                GameCommon[kind] = function(self, ...)
                    local physicsId = self:generateId()
                    self:send({ kind = kind }, physicsId, ...)
                    return physicsId
                end
            end
        end
    end

    definePhysicsConstructors({
        'newBody', 'newChainShape', 'newCircleShape', 'newDistanceJoint',
        'newEdgeShape', 'newFixture', 'newFrictionJoint', 'newGearJoint',
        'newMotorJoint', 'newMouseJoint', 'newPolygonShape', 'newPrismaticJoint',
        'newPulleyJoint', 'newRectangleShape', 'newRevoluteJoint', 'newRopeJoint',
        'newWeldJoint', 'newWheelJoint', 'newWorld',
    })

    local function definePhysicsReliableMethods(methodNames) -- For any `:<foo>` method, first arg is `physicsId` of target
        for _, methodName in ipairs(methodNames) do
            local kind = 'physics_' .. methodName

            self:defineMessageKind(kind, {
                to = 'all',
                reliable = true,
                channel = PHYSICS_RELIABLE_CHANNEL,
                selfSend = true,
                forward = true,
            })

            if not GameCommon.receivers[kind] then
                GameCommon.receivers[kind] = function(self, time, physicsId, ...)
                    (function (...)
                        local obj = self.physicsIdToObject[physicsId]
                        if not obj then
                            error("no / bad `physicsId` given as first parameter to '" .. kind .. "'")
                        end
                        obj[methodName](obj, ...)
                    end)(self:physics_resolveIds(...))
                end

                GameCommon[kind] = function(self, ...)
                    self:send({ kind = kind }, ...)
                end
            end
        end
    end

    definePhysicsReliableMethods({
        -- Setters
        'setActive', 'setAngle', 'setAngularDamping', 'setAngularOffset',
        'setAngularVelocity', 'setAwake', 'setBullet', 'setCategory',
        'setContactFilter', 'setCorrectionFactor', 'setDampingRatio', 'setDensity',
        'setEnabled', 'setFilterData', 'setFixedRotation', 'setFrequency',
        'setFriction', 'setGravity', 'setGravityScale', 'setGroupIndex', 'setInertia',
        'setLength', 'setLimits', 'setLimitsEnabled', 'setLinearDamping',
        'setLinearOffset', 'setLinearVelocity', 'setLowerLimit', 'setMask', 'setMass',
        'setMassData', 'setMaxForce', 'setMaxLength', 'setMaxMotorForce',
        'setMaxMotorTorque', 'setMaxTorque', 'setMotorEnabled', 'setMotorSpeed',
        'setNextVertex', 'setPoint', 'setPosition', 'setPreviousVertex', 'setRadius',
        'setRatio', 'setRestitution', 'setSensor', 'setSleepingAllowed',
        'setSpringDampingRatio', 'setSpringFrequency', 'setTangentSpeed', 'setTarget',
        'setType', 'setUpperLimit', 'setX', 'setY',
    })

    self:defineMessageKind('physics_destroyObject', {
        from = 'server',
        to = 'all',
        reliable = true,
        channel = PHYSICS_RELIABLE_CHANNEL,
        selfSend = true,
        forward = true,
    })

    self:defineMessageKind('physics_setOwner', {
        to = 'all',
        reliable = true,
        channel = PHYSICS_RELIABLE_CHANNEL,
        selfSend = true,
        forward = true,
    })

    self:defineMessageKind('physics_serverBodySyncs', {
        from = 'server',
        channel = PHYSICS_SERVER_SYNCS_CHANNEL,
        reliable = false,
        rate = 10,
        selfSend = false,
    })

    self:defineMessageKind('physics_clientBodySync', {
        from = 'client',
        channel = PHYSICS_CLIENT_SYNCS_CHANNEL,
        reliable = false,
        rate = 30,
        selfSend = false,
        forward = true,
    })

    --
    -- Scene
    --

    -- Client requests server to create the scene
    self:defineMessageKind('createMainWorld', {
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        forward = false,
        selfSend = false,
    })

    -- Client receives `physicsId` of the world when the scene is created
    self:defineMessageKind('mainWorldId', {
        to = 'all',
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = true,
    })

    --
    -- Touches
    --

    -- Client tells everyone about a touch press
    self:defineMessageKind('addTouch', {
        reliable = true,
        channel = TOUCHES_CHANNEL,
        forward = true,
        selfSend = true,
    })

    -- Client tells everyone about a touch release
    self:defineMessageKind('removeTouch', {
        reliable = true,
        channel = TOUCHES_CHANNEL,
        forward = true,
        forwardToOrigin = true,
        selfSend = false,
    })

    -- Client tells everyone about a touch move
    self:defineMessageKind('touchPosition', {
        reliable = false,
        channel = TOUCHES_CHANNEL,
        forward = true,
        forwardToOrigin = true,
        selfSend = false,
        rate = 30,
    })
end


-- Start / stop

function GameCommon:start()
    self.mes = {}

    self.physicsIdToObject = {} -- `physicsId` -> `World` / `Body` / `Fixture` / `Shape` / ...
    self.physicsObjectToId = {}

    self.physicsObjectIdToOwnerId = {} -- `physicsId` -> `clientId`
    self.physicsOwnerIdToObjectIds = {} -- `clientId` -> `physicsId` -> `true`
    setmetatable(self.physicsOwnerIdToObjectIds, {
        __index = function(t, k)
            local v = {}
            t[k] = v
            return v
        end,
    })

    self.mainWorldId = nil

    self.touches = {} --> `touchId` -> `{ clientId, finished, x, y, binding = { bodyId, localX, localY }, positionHistory = { { time, x, y }, ... } }`
    self.bodyIdToTouchId = {}
end


-- Mes

function GameCommon.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end


-- Physics

function GameCommon:physics_resolveIds(...)
    if select('#', ...) == 0 then
        return
    end
    local firstArg = select(1, ...)
    return self.physicsIdToObject[firstArg] or firstArg, self:physics_resolveIds(select(2, ...))
end

function GameCommon.receivers:physics_destroyObject(time, physicsId)
    local obj = self.physicsIdToObject[physicsId]
    if not obj then
        error("physics_destroyObject: no / bad `physicsId`")
    end

    self.physicsIdToObject[physicsId] = nil
    self.physicsObjectToId[obj] = nil

    obj:destroy()
end

function GameCommon.receivers:physics_setOwner(time, physicsId, newOwnerId)
    local currentOwnerId = self.physicsObjectIdToOwnerId[physicsId]
    if newOwnerId == nil then -- Removing owner
        if currentOwnerId == nil then
            return
        else
            self.physicsObjectIdToOwnerId[physicsId] = nil
            self.physicsOwnerIdToObjectIds[currentOwnerId][physicsId] = nil
        end
    else -- Setting owner
        if currentOwnerId ~= nil then -- Already owned by someone?
            if currentOwnerId == newOwnerId then
                return -- Already owned by this client, nothing to do
            else
                error("physics_setOwner: object already owned by different client")
            end
        end

        self.physicsObjectIdToOwnerId[physicsId] = newOwnerId
        self.physicsOwnerIdToObjectIds[newOwnerId][physicsId] = true
    end
end

function GameCommon:physics_getBodySync(body)
    local x, y = body:getPosition()
    local vx, vy = body:getLinearVelocity()
    local a = body:getAngle()
    local va = body:getAngularVelocity()
    return x, y, vx, vy, a, va
end

function GameCommon:physics_applyBodySync(body, x, y, vx, vy, a, va)
    body:setPosition(x, y)
    body:setLinearVelocity(vx, vy)
    body:setAngle(a)
    body:setAngularVelocity(va)
end

function GameCommon.receivers:physics_serverBodySyncs(time, syncs)
    for bodyId, sync in pairs(syncs) do
        local body = self.physicsIdToObject[bodyId]
        if body then
            self:physics_applyBodySync(body, unpack(sync))
        end
    end
end

function GameCommon.receivers:physics_clientBodySync(time, bodyId, ...)
    local body = self.physicsIdToObject[bodyId]
    if body then
        self:physics_applyBodySync(body, ...)
    end
end


-- Scene

function GameCommon.receivers:mainWorldId(time, mainWorldId)
    self.mainWorldId = mainWorldId
end


-- Touches

function GameCommon.receivers:addTouch(time, clientId, touchId, x, y, bodyId, localX, localY)
    -- Create touch entry
    self.touches[touchId] = {
        clientId = clientId,
        finished = false,
        x = x,
        y = y,
        positionHistory = {
            {
                time = time,
                x = x,
                y = y,
            },
        },
        binding = {
            bodyId = bodyId,
            localX = localX,
            localY = localY,
        },
    }
    self.bodyIdToTouchId[bodyId] = touchId
end

function GameCommon.receivers:removeTouch(time, touchId)
    local touch = assert(self.touches[touchId], 'removeTouch: no such touch')
    touch.removed = true -- We keep it around till the history is exhausted
end

function GameCommon.receivers:touchPosition(time, touchId, x, y)
    local touch = assert(self.touches[touchId], 'touchPosition: no such touch')
    table.insert(touch.positionHistory, {
        time = time,
        x = x,
        y = y,
    })
end


-- Update

function GameCommon:update(dt)
    -- Set `self.mainWorld` from `self.mainWorldId`
    if not self.mainWorld then
        if self.mainWorldId then
            self.mainWorld = self.physicsIdToObject[self.mainWorldId]
        end
    end

    -- Interpolate touches and apply forces to bound bodies
    do
        local interpTime = self.time - 0.13
        for touchId, touch in pairs(self.touches) do
            local history = touch.positionHistory

            -- Remove position if next one is also before interpolation time -- we need one before and one after
            while #history >= 2 and history[1].time < interpTime and history[2].time < interpTime do
                table.remove(history, 1)
            end

            -- Update position
            if #history >= 2 then
                -- Have one before and one after, interpolate
                local f = (interpTime - history[1].time) / (history[2].time - history[1].time)
                local dx, dy = history[2].x - history[1].x, history[2].y - history[1].y
                touch.x, touch.y = history[1].x + f * dx, history[1].y + f * dy
            elseif #history == 1 then
                -- Have only one before, just set
                touch.x, touch.y = history[1].x, history[1].y
            end

            -- If at end of history and it's removed, get rid of this touch
            if #history <= 1 and touch.removed then
                if touch.binding then -- Free the binding
                    self.bodyIdToTouchId[touch.binding.bodyId] = nil
                end

                self.touches[touchId] = nil
            else
                -- If bound to a body, apply an impulse on it
                if touch.binding then
                    local body = self.physicsIdToObject[touch.binding.bodyId]

                    local newX, newY = touch.x - touch.binding.localX, touch.y - touch.binding.localY
                    local currX, currY = body:getPosition()
                    local dispX, dispY = newX - currX, newY - currY

                    body:setLinearVelocity(0, 0)
                    body:setAngularVelocity(0)
                    body:setLinearVelocity(dispX / dt, dispY / dt)
                end
            end
        end
    end

    -- Do a physics step
    if self.mainWorld then
        self.mainWorld:update(dt)
    end
end