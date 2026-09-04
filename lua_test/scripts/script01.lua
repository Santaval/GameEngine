-- GLOBAL VARIABLES
var_nombre = "Aaron Santana"
var_edad = 22

table_config = {
    title = "Lua Game Engine",
    fullscreen = true,
    resolution = {
        width = 800,
        height = 600
    }
}

function factorial(n)
    if n == 0 then
        return 1
    else
        return n * factorial(n - 1)
    end
end

print("[LUA] Nombre: " .. var_nombre)
print("[LUA] Edad: " .. var_edad)


var_pow = pow(2, 4)

print("[LUA] 2^4 = " .. var_pow)