"""运行方式：python 框架学习/test_react_agent.py"""

from dotenv import load_dotenv
from hello_agents import HelloAgentsLLM, ReActAgent, ToolRegistry
from hello_agents.tools import CalculatorTool

from react_prompt import MY_REACT_PROMPT


class MyReActAgent(ReActAgent):
    """沿用框架的ReAct执行流程，默认使用自己的提示词。"""

    def __init__(
        self,
        name,
        llm,
        tool_registry,
        system_prompt=None,
        config=None,
        max_steps=5,
        custom_prompt=None,
    ):
        super().__init__(
            name=name,
            llm=llm,
            tool_registry=tool_registry,
            system_prompt=system_prompt,
            config=config,
            max_steps=max_steps,
            custom_prompt=MY_REACT_PROMPT if custom_prompt is None else custom_prompt,
        )


def main():
    load_dotenv()

    tool_registry = ToolRegistry()
    tool_registry.register_tool(CalculatorTool())

    agent = MyReActAgent(
        name="ReAct助手",
        llm=HelloAgentsLLM(),
        tool_registry=tool_registry,
        custom_prompt=MY_REACT_PROMPT,
        max_steps=5,
    )

    result = agent.run("请使用计算器计算 15 * 8 + 32")
    print(f"最终回答: {result}")


if __name__ == "__main__":
    main()
