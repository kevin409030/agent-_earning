# 配置好同级文件夹下.env中的大模型API, 可参考code文件夹配套的.env.example，也可以拿前几章的案例的.env文件复用。
import os
from pathlib import Path

from hello_agents import SimpleAgent, HelloAgentsLLM
from my_llm import MyLLM

from dotenv import load_dotenv

env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(env_path, override=True)

print("配置文件：", env_path)
print("配置地址：", repr(os.getenv("LLM_BASE_URL")))

# 显式使用 .env 中的客户端地址，避免被系统的 OLLAMA_HOST 监听地址覆盖。
llm = HelloAgentsLLM(
    provider="ollama",
    base_url=os.getenv("LLM_BASE_URL"),
)
print("实际模型地址：", llm.base_url)

#创建simpleagent
agent = SimpleAgent(
    name = "AI助手",
    llm = llm,
    system_prompt="你是一个有用的ai助手"
)


#基础对话
response = agent.run("你好请介绍一下自己")
print(response)

#添加工具功能
from hello_agents.tools import  CalculatorTool
calculatortool = CalculatorTool()

response = agent.run("请帮我计算4*10")
print(response)

print(f"历史消息数:{len(agent.get_history())}")


