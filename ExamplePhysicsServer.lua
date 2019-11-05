require 'server' -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExamplePhysicsCommon'


-- Connect / disconnect

function GameServer:connect(clientId)
    -- Send full state to new client
    self:send({
        to = clientId,
        kind = 'fullState',
    }, {
        mes = self.mes,
    })

    -- Construct physics objects
end

function GameServer:disconnect(clientId)
end


-- Scene

function GameServer.receivers:createMainWorld()
    if self.mainWorldId then
        return
    end

    local worldId = self:physics_newWorld(0, 0, true)


    -- Walls

    local function createWall(x, y, width, height)
        local bodyId = self:physics_newBody(worldId, x, y)
        local shapeId = self:physics_newRectangleShape(width, height)
        local fixtureId = self:physics_newFixture(bodyId, shapeId)
    end

    local wallThickness = 20

    createWall(800 / 2, wallThickness / 2, 800, wallThickness)
    createWall(800 / 2, 450 - wallThickness / 2, 800, wallThickness)
    createWall(wallThickness / 2, 450 / 2, wallThickness, 450)
    createWall(800 - wallThickness / 2, 450 / 2, wallThickness, 450)


    -- Dynamic bodies

    local function createDynamicBody(shapeId)
        local bodyId = self:physics_newBody(worldId, math.random(70, 800 - 70), math.random(70, 450 - 70), 'dynamic')
        local fixtureId = self:physics_newFixture(bodyId, shapeId, 1.5)
        self:physics_setRestitution(fixtureId, 0.6)
        self:physics_setAngularDamping(bodyId, 1.6)
        self:physics_setLinearDamping(bodyId, 2.2)
    end

    for i = 1, 5 do -- Balls
        createDynamicBody(self:physics_newCircleShape(20))
    end

    for i = 1, 5 do -- Small boxes
        createDynamicBody(self:physics_newRectangleShape(40, 40))
    end

    for i = 1, 2 do -- Big boxes
        createDynamicBody(self:physics_newRectangleShape(math.random(90, 120), math.random(200, 300)))
    end


    self:send({ kind = 'mainWorldId' }, worldId)
end


-- Update

function GameServer:update(dt)
    -- Common update
    GameCommon.update(self, dt)

    -- Send body syncs
    if self.mainWorld then
        for clientId in pairs(self._clientIds) do
            local syncs = {}
            for _, body in ipairs(self.mainWorld:getBodies()) do
                if body:isAwake() then
                    local bodyId = self.physicsObjectToId[body]
                    local ownerId = self.physicsObjectIdToOwnerId[bodyId]
                    if ownerId == nil then -- Clients will send syncs for bodies they own
                        syncs[bodyId] = { self:physics_getBodySync(body) }
                    end
                end
            end
            self:send({
                kind = 'physics_serverBodySyncs',
                to = clientId,
            }, syncs)
        end
    end
end