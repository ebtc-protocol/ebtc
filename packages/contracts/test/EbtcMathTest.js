const EbtcMathTester = artifacts.require("./EbtcMathTester.sol")

contract('EbtcMath', async accounts => {
  
  beforeEach('deploy tester', async () => {
    ebtcMathTester = await EbtcMathTester.new()
  })

  const checkFunction = async (func, cond, params) => {
    assert.equal(await ebtcMathTester[func](...params), cond(...params))
  }

  it('max works if a > b', async () => {
    await checkFunction('callMax', (a, b) => Math.max(a, b), [2, 1])
  })

  it('max works if a = b', async () => {
    await checkFunction('callMax', (a, b) => Math.max(a, b), [2, 2])
  })

  it('max works if a < b', async () => {
    await checkFunction('callMax', (a, b) => Math.max(a, b), [1, 2])
  })
})
