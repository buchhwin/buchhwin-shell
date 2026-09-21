.pragma library

// Safe arithmetic evaluator (recursive descent, no eval):
//   numbers (1.5, 1,5, 2e3), + - * / % ^, parentheses, unary minus,
//   constants pi, e and functions sqrt abs round floor ceil sin cos tan ln log.
// evaluate() returns { ok, value } or { ok: false, error }.

var FUNCTIONS = {
    sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, ln: Math.log, log: Math.log10
}
var CONSTANTS = { pi: Math.PI, e: Math.E }

function tokenize(input) {
    const tokens = []
    let i = 0
    while (i < input.length) {
        const char = input[i]
        if (/\s/.test(char)) { i++; continue }
        if (/[0-9.,]/.test(char)) {
            let text = ""
            while (i < input.length && /[0-9.,]/.test(input[i])) text += input[i++]
            if (i < input.length && /[eE]/.test(input[i]) && /[0-9+-]/.test(input[i + 1] || "")) {
                text += input[i++]
                if (/[+-]/.test(input[i])) text += input[i++]
                while (i < input.length && /[0-9]/.test(input[i])) text += input[i++]
            }
            const normalized = text.replace(",", ".")
            if ((normalized.match(/\./g) || []).length > 1 || !isFinite(Number(normalized)))
                throw new Error("Invalid number")
            tokens.push({ type: "number", value: Number(normalized) })
            continue
        }
        if (/[a-z]/i.test(char)) {
            let name = ""
            while (i < input.length && /[a-z0-9]/i.test(input[i])) name += input[i++]
            name = name.toLowerCase()
            if (FUNCTIONS[name] === undefined && CONSTANTS[name] === undefined)
                throw new Error("Unknown: " + name)
            tokens.push({ type: "name", value: name })
            continue
        }
        if ("+-*/%^()×÷".indexOf(char) >= 0) {
            tokens.push({ type: "op", value: char === "×" ? "*" : char === "÷" ? "/" : char })
            i++
            continue
        }
        throw new Error("Invalid character")
    }
    return tokens
}

function parse(tokens) {
    let position = 0
    const peek = () => tokens[position]
    const take = () => tokens[position++]
    const isOp = (value) => peek() && peek().type === "op" && peek().value === value

    function expression() {
        let value = term()
        while (isOp("+") || isOp("-")) value = take().value === "+" ? value + term() : value - term()
        return value
    }
    function term() {
        let value = unary()
        while (isOp("*") || isOp("/") || isOp("%")) {
            const op = take().value
            const right = unary()
            if ((op === "/" || op === "%") && right === 0) throw new Error("Division by 0")
            value = op === "*" ? value * right : op === "/" ? value / right : value % right
        }
        return value
    }
    function unary() {
        if (isOp("-")) { take(); return -unary() }
        if (isOp("+")) { take(); return unary() }
        return power()
    }
    function power() {
        const base = primary()
        if (isOp("^")) { take(); return Math.pow(base, unary()) }
        return base
    }
    function primary() {
        const token = take()
        if (!token) throw new Error("Incomplete")
        if (token.type === "number") return token.value
        if (token.type === "name") {
            if (CONSTANTS[token.value] !== undefined) return CONSTANTS[token.value]
            if (!isOp("(")) throw new Error("Parenthesis expected")
            take()
            const argument = expression()
            if (!isOp(")")) throw new Error("Missing parenthesis")
            take()
            return FUNCTIONS[token.value](argument)
        }
        if (token.value === "(") {
            const value = expression()
            if (!isOp(")")) throw new Error("Missing parenthesis")
            take()
            return value
        }
        throw new Error("Unexpected: " + token.value)
    }

    const result = expression()
    if (position < tokens.length) throw new Error("Unexpected: " + tokens[position].value)
    return result
}

function evaluate(input) {
    try {
        const tokens = tokenize(String(input))
        if (!tokens.length) return { ok: false, error: "Empty" }
        const value = parse(tokens)
        if (!isFinite(value)) return { ok: false, error: "Undefined" }
        return { ok: true, value: value }
    } catch (error) {
        return { ok: false, error: error.message }
    }
}

// Heuristic for inline results without the "=" prefix.
function looksLikeMath(input) {
    return /[0-9)]\s*[-+*/%^×÷]\s*[-0-9(a-z]/i.test(input) || /^\s*(sqrt|abs|round|floor|ceil|sin|cos|tan|ln|log)\s*\(/i.test(input)
}

function format(value) {
    if (Math.abs(value) >= 1e15 || (Math.abs(value) < 1e-9 && value !== 0)) return value.toExponential(6)
    return String(Math.round(value * 1e10) / 1e10)
}
