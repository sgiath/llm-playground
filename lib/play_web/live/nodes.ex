defmodule Play.Web.Live.Nodes do
  # ============================================================================
  # Node Type Definitions
  # ============================================================================

  # Define all available node types for LLM agent workflows.
  # Each node type is a map with the following keys:
  # - type: unique identifier (required)
  # - title: display name
  # - description: help text
  # - category: category path (e.g., "llm", "agent", "input", "output", "utility")
  # - inputs: list of %{name: string, type: string | nil}
  # - outputs: list of %{name: string, type: string | nil}
  # - properties: list of %{name: string, default: any}
  # - widgets: list of widget definitions
  # - size: [width, height]
  # - color: node header color
  # - bgcolor: node body color
  # - execute_code: JavaScript code for onExecute (receives inputs array and properties)
  # - display_value: %{property: string, font: string, color: string} for displaying value
  def node_types do
    [
      # LLM Provider nodes
      openai_node(),
      anthropic_node(),
      google_ai_node(),
      xai_node(),

      # Agent nodes
      stateless_agent_node(),
      stateful_agent_node(),

      # Input nodes
      text_input_node(),
      number_input_node(),
      variable_node(),

      # Output nodes
      display_node(),
      console_node(),

      # Utility nodes
      message_builder_node(),
      messages_combiner_node(),
      prompt_template_node(),
      json_parse_node(),
      condition_node(),

      # Tool nodes
      web_search_tool_node(),
      tools_combiner_node()
    ]
  end

  # ============================================================================
  # LLM Provider Nodes
  # ============================================================================

  defp openai_node do
    %{
      type: "openai",
      title: "OpenAI",
      description: "OpenAI LLM configuration",
      category: "llm",
      inputs: [],
      outputs: [%{name: "llm_config", type: "llm_config"}],
      properties: [
        %{name: "model", default: "gpt-5.2"},
        %{name: "reasoning_effort", default: "medium"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Model",
          property: "model",
          default: "gpt-5.2",
          options: %{
            values: ["gpt-5.2", "gpt-5.2-pro", "gpt-5-mini", "gpt-5-nano"]
          }
        },
        %{
          type: "combo",
          name: "Reasoning",
          property: "reasoning_effort",
          default: "medium",
          options: %{
            values: ["none", "minimal", "low", "medium", "high", "xhigh"]
          }
        }
      ],
      size: [200, 140],
      color: "#10a37f",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        provider: 'openai',
        model: properties.model,
        reasoning_effort: properties.reasoning_effort
      };
      """
    }
  end

  defp anthropic_node do
    %{
      type: "anthropic",
      title: "Anthropic",
      description: "Anthropic Claude LLM configuration",
      category: "llm",
      inputs: [],
      outputs: [%{name: "llm_config", type: "llm_config"}],
      properties: [
        %{name: "model", default: "claude-sonnet-4-5"},
        %{name: "reasoning_effort", default: "medium"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Model",
          property: "model",
          default: "claude-sonnet-4-5",
          options: %{
            values: [
              "claude-sonnet-4-5",
              "claude-opus-4-5",
              "claude-haiku-4-5"
            ]
          }
        },
        %{
          type: "combo",
          name: "Reasoning",
          property: "reasoning_effort",
          default: "medium",
          options: %{
            values: ["none", "minimal", "low", "medium", "high", "xhigh"]
          }
        }
      ],
      size: [220, 140],
      color: "#cc785c",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        provider: 'anthropic',
        model: properties.model,
        reasoning_effort: properties.reasoning_effort
      };
      """
    }
  end

  defp google_ai_node do
    %{
      type: "google_ai",
      title: "Google AI",
      description: "Google Gemini LLM configuration",
      category: "llm",
      inputs: [],
      outputs: [%{name: "llm_config", type: "llm_config"}],
      properties: [
        %{name: "model", default: "gemini-3-pro-preview"},
        %{name: "reasoning_effort", default: "medium"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Model",
          property: "model",
          default: "gemini-3-pro-preview",
          options: %{
            values: [
              "gemini-3-pro-preview",
              "gemini-3-flash-preview"
            ]
          }
        },
        %{
          type: "combo",
          name: "Reasoning",
          property: "reasoning_effort",
          default: "medium",
          options: %{
            values: ["none", "minimal", "low", "medium", "high", "xhigh"]
          }
        }
      ],
      size: [200, 140],
      color: "#4285f4",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        provider: 'google_ai',
        model: properties.model,
        reasoning_effort: properties.reasoning_effort
      };
      """
    }
  end

  defp xai_node do
    %{
      type: "xai",
      title: "xAI Grok",
      description: "xAI Grok LLM configuration",
      category: "llm",
      inputs: [],
      outputs: [%{name: "llm_config", type: "llm_config"}],
      properties: [
        %{name: "model", default: "grok-4-1-fast"},
        %{name: "reasoning_effort", default: "medium"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Model",
          property: "model",
          default: "grok-4-1-fast",
          options: %{
            values: [
              "grok-4-1-fast",
              "grok-4-1-fast-non-reasoning",
              "grok-code-fast-1",
              "grok-4-fast",
              "grok-4-fast-non-reasoning",
              "grok-4",
              "grok-3-mini",
              "grok-3"
            ]
          }
        },
        %{
          type: "combo",
          name: "Reasoning",
          property: "reasoning_effort",
          default: "medium",
          options: %{
            values: ["none", "minimal", "low", "medium", "high", "xhigh"]
          }
        }
      ],
      size: [220, 140],
      color: "#ffffff",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        provider: 'xai',
        model: properties.model,
        reasoning_effort: properties.reasoning_effort
      };
      """
    }
  end

  # ============================================================================
  # Agent Nodes
  # ============================================================================

  defp stateless_agent_node do
    %{
      type: "stateless_agent",
      title: "Stateless Agent",
      description:
        "LLM Agent that processes messages with a system prompt and optional tools. Does not retain conversation history between runs.",
      category: "agent",
      inputs: [
        %{name: "llm_config", type: "llm_config"},
        %{name: "system", type: "text"},
        %{name: "messages", type: "messages"},
        %{name: "tools", type: "tools"}
      ],
      outputs: [
        %{name: "response", type: "text"},
        %{name: "messages_out", type: "messages"},
        %{name: "tool_calls", type: "tool_calls"}
      ],
      properties: [
        %{name: "system_prompt", default: "You are a helpful assistant."},
        %{name: "stream", default: false}
      ],
      widgets: [
        %{
          type: "text",
          name: "System Prompt",
          property: "system_prompt",
          default: "You are a helpful assistant.",
          options: %{multiline: true}
        },
        %{
          type: "toggle",
          name: "Stream",
          property: "stream",
          default: false
        }
      ],
      # Hide "System Prompt" widget when "system" input is connected
      hide_widget_on_input: %{"system" => "System Prompt"},
      size: [280, 150],
      color: "#9333ea",
      bgcolor: "#1e1e2f",
      execute_code: """
      const llm_config = inputs[0];
      const system_override = inputs[1];
      const messages = inputs[2] || [];
      const tools = inputs[3] || [];
      const system_prompt = system_override || properties.system_prompt;

      // Store config for server-side execution
      this.properties._pending_execution = {
        llm_config: llm_config,
        messages: messages,
        tools: tools,
        system_prompt: system_prompt,
        stream: properties.stream
      };

      // Return current stored response (will be updated by server)
      return { 
        0: this.properties._last_response || '',
        1: this.properties._messages_out || messages,
        2: this.properties._tool_calls || []
      };
      """
    }
  end

  defp stateful_agent_node do
    %{
      type: "stateful_agent",
      title: "Stateful Agent",
      description:
        "LLM Agent that maintains conversation history across workflow runs. Each run appends to the conversation.",
      category: "agent",
      inputs: [
        %{name: "llm_config", type: "llm_config"},
        %{name: "system", type: "text"},
        %{name: "user_message", type: "text"},
        %{name: "tools", type: "tools"}
      ],
      outputs: [
        %{name: "response", type: "text"},
        %{name: "messages_out", type: "messages"},
        %{name: "tool_calls", type: "tool_calls"}
      ],
      properties: [
        %{name: "system_prompt", default: "You are a helpful assistant."},
        %{name: "stream", default: false},
        %{name: "conversation_history", default: []}
      ],
      widgets: [
        %{
          type: "text",
          name: "System Prompt",
          property: "system_prompt",
          default: "You are a helpful assistant.",
          options: %{multiline: true}
        },
        %{
          type: "toggle",
          name: "Stream",
          property: "stream",
          default: false
        },
        %{
          type: "button",
          name: "Clear History",
          callback: "clearConversationHistory"
        }
      ],
      # Hide "System Prompt" widget when "system" input is connected
      hide_widget_on_input: %{"system" => "System Prompt"},
      size: [280, 170],
      color: "#7c3aed",
      bgcolor: "#1e1e2f",
      execute_code: """
      const llm_config = inputs[0];
      const system_override = inputs[1];
      const user_message = inputs[2];
      const tools = inputs[3] || [];
      const system_prompt = system_override || properties.system_prompt;
      const conversation_history = properties.conversation_history || [];

      // Store config for server-side execution
      this.properties._pending_execution = {
        llm_config: llm_config,
        user_message: user_message,
        tools: tools,
        system_prompt: system_prompt,
        stream: properties.stream,
        conversation_history: conversation_history
      };

      // Return current stored response (will be updated by server)
      return { 
        0: this.properties._last_response || '',
        1: this.properties.conversation_history || [],
        2: this.properties._tool_calls || []
      };
      """
    }
  end

  # ============================================================================
  # Input Nodes
  # ============================================================================

  defp text_input_node do
    %{
      type: "text_input",
      title: "Text Input",
      description: "Enter text input for the workflow",
      category: "input",
      outputs: [%{name: "text", type: "text"}],
      properties: [%{name: "value", default: ""}],
      widgets: [
        %{
          type: "text",
          name: "Text",
          property: "value",
          default: "",
          options: %{multiline: true}
        }
      ],
      size: [220, 80],
      color: "#22c55e",
      bgcolor: "#1a1a2e",
      execute_code: "return properties.value;"
    }
  end

  defp number_input_node do
    %{
      type: "number_input",
      title: "Number Input",
      description: "Enter a numeric value for the workflow",
      category: "input",
      outputs: [%{name: "number", type: "number"}],
      properties: [
        %{name: "value", default: 0},
        %{name: "min", default: nil},
        %{name: "max", default: nil},
        %{name: "step", default: 1}
      ],
      widgets: [
        %{
          type: "number",
          name: "Value",
          property: "value",
          default: 0,
          options: %{step: 1}
        }
      ],
      size: [180, 60],
      color: "#22c55e",
      bgcolor: "#1a1a2e",
      execute_code: "return properties.value;"
    }
  end

  defp variable_node do
    %{
      type: "variable",
      title: "Variable",
      description: "Named variable with a default value",
      category: "input",
      outputs: [%{name: "value", type: nil}],
      properties: [
        %{name: "name", default: "my_var"},
        %{name: "default_value", default: ""}
      ],
      widgets: [
        %{
          type: "text",
          name: "Name",
          property: "name",
          default: "my_var"
        },
        %{
          type: "text",
          name: "Default",
          property: "default_value",
          default: ""
        }
      ],
      size: [180, 90],
      color: "#22c55e",
      bgcolor: "#1a1a2e",
      execute_code: "return properties.default_value;"
    }
  end

  # ============================================================================
  # Output Nodes
  # ============================================================================

  defp display_node do
    %{
      type: "display",
      title: "Display",
      description: "Displays the input value on the node",
      category: "output",
      inputs: [%{name: "value", type: nil}],
      properties: [%{name: "value", default: ""}],
      size: [300, 80],
      color: "#f59e0b",
      bgcolor: "#1a1a2e",
      resizable: true,
      execute_code: """
      const val = inputs[0];
      this.properties.value = typeof val === 'object' ? JSON.stringify(val, null, 2) : String(val ?? '');
      """,
      display_value: %{property: "value", font: "14px monospace", color: "#fff"}
    }
  end

  defp console_node do
    %{
      type: "console",
      title: "Console",
      description: "Logs the input value to console",
      category: "output",
      inputs: [%{name: "value", type: nil}],
      properties: [%{name: "prefix", default: ""}],
      widgets: [
        %{
          type: "text",
          name: "Prefix",
          property: "prefix",
          default: ""
        }
      ],
      size: [180, 60],
      color: "#f59e0b",
      bgcolor: "#1a1a2e",
      execute_code: """
      const prefix = properties.prefix ? properties.prefix + ': ' : '';
      console.log(prefix, inputs[0]);
      """
    }
  end

  # ============================================================================
  # Utility Nodes
  # ============================================================================

  defp message_builder_node do
    %{
      type: "message_builder",
      title: "Message Builder",
      description: "Builds a message with role and content",
      category: "utility",
      inputs: [%{name: "content", type: "text"}],
      outputs: [%{name: "message", type: "message"}],
      properties: [
        %{name: "role", default: "user"},
        %{name: "content", default: ""}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Role",
          property: "role",
          default: "user",
          options: %{values: ["user", "assistant"]}
        },
        %{
          type: "text",
          name: "Content",
          property: "content",
          default: "",
          options: %{multiline: true}
        }
      ],
      # Hide "Content" widget when "content" input is connected
      hide_widget_on_input: %{"content" => "Content"},
      size: [200, 90],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      execute_code: """
      const content = inputs[0] || properties.content;
      return { role: properties.role, content: content };
      """
    }
  end

  defp messages_combiner_node do
    %{
      type: "messages_combiner",
      title: "Messages",
      description: "Combines multiple messages into an array. Right-click to add/remove inputs.",
      category: "utility",
      inputs: [
        %{name: "msg1", type: "message"}
      ],
      outputs: [%{name: "messages", type: "messages"}],
      properties: [%{name: "input_count", default: 1}],
      size: [160, 60],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      # Enable dynamic inputs - the JS hook will add menu options to add/remove
      dynamic_inputs: %{
        type: "message",
        name_prefix: "msg",
        min: 1,
        max: 20,
        # Automatically add a new input when the last one is connected
        auto_add: true
      },
      execute_code: """
      const messages = [];
      for (let i = 0; i < inputs.length; i++) {
        if (inputs[i] && typeof inputs[i] === 'object' && inputs[i].role && inputs[i].content) {
          messages.push(inputs[i]);
        }
      }
      return messages;
      """
    }
  end

  defp prompt_template_node do
    %{
      type: "prompt_template",
      title: "Prompt Template",
      description: "String interpolation with {{variable}} syntax",
      category: "utility",
      inputs: [
        %{name: "var1", type: "text"},
        %{name: "var2", type: "text"},
        %{name: "var3", type: "text"}
      ],
      outputs: [%{name: "text", type: "text"}],
      properties: [
        %{name: "template", default: "Hello {{var1}}!"},
        %{name: "var1_name", default: "var1"},
        %{name: "var2_name", default: "var2"},
        %{name: "var3_name", default: "var3"}
      ],
      widgets: [
        %{
          type: "text",
          name: "Template",
          property: "template",
          default: "Hello {{var1}}!"
        },
        %{
          type: "text",
          name: "Var1 Name",
          property: "var1_name",
          default: "var1"
        },
        %{
          type: "text",
          name: "Var2 Name",
          property: "var2_name",
          default: "var2"
        },
        %{
          type: "text",
          name: "Var3 Name",
          property: "var3_name",
          default: "var3"
        }
      ],
      size: [240, 150],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      execute_code: """
      let result = properties.template;
      const vars = {
        [properties.var1_name]: inputs[0] || '',
        [properties.var2_name]: inputs[1] || '',
        [properties.var3_name]: inputs[2] || ''
      };
      for (const [key, value] of Object.entries(vars)) {
        result = result.replace(new RegExp('\\\\{\\\\{' + key + '\\\\}\\\\}', 'g'), value);
      }
      return result;
      """
    }
  end

  defp json_parse_node do
    %{
      type: "json_parse",
      title: "JSON Parse",
      description: "Parses a JSON string into an object",
      category: "utility",
      inputs: [%{name: "text", type: "text"}],
      outputs: [%{name: "object", type: nil}],
      size: [160, 50],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      execute_code: """
      try {
        return JSON.parse(inputs[0] || '{}');
      } catch (e) {
        return { error: e.message };
      }
      """
    }
  end

  defp condition_node do
    %{
      type: "condition",
      title: "Condition",
      description: "Routes value based on condition",
      category: "utility",
      inputs: [
        %{name: "value", type: nil},
        %{name: "condition", type: "boolean"}
      ],
      outputs: [
        %{name: "true", type: nil},
        %{name: "false", type: nil}
      ],
      properties: [%{name: "check_truthy", default: false}],
      widgets: [
        %{
          type: "toggle",
          name: "Check Truthy",
          property: "check_truthy",
          default: false
        }
      ],
      size: [160, 70],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      execute_code: """
      const value = inputs[0];
      let cond = inputs[1];
      if (properties.check_truthy) {
        cond = !!value;
      }
      return cond ? { 0: value, 1: null } : { 0: null, 1: value };
      """
    }
  end

  # ============================================================================
  # Tool Nodes
  # ============================================================================

  defp web_search_tool_node do
    %{
      type: "web_search_tool",
      title: "Web Search",
      description: "Defines a web search tool for the Agent. The LLM decides when to call it.",
      category: "tool",
      outputs: [%{name: "tool", type: "tool"}],
      properties: [
        %{name: "provider", default: "tavily"},
        %{name: "max_results", default: 5},
        %{name: "search_depth", default: "basic"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Provider",
          property: "provider",
          default: "tavily",
          options: %{
            values: ["tavily", "serper", "brave", "duckduckgo", "exa"]
          }
        },
        %{
          type: "number",
          name: "Max Results",
          property: "max_results",
          default: 5,
          options: %{min: 1, max: 20, step: 1}
        },
        %{
          type: "combo",
          name: "Search Depth",
          property: "search_depth",
          default: "basic",
          options: %{
            values: ["basic", "advanced"]
          }
        }
      ],
      size: [200, 110],
      color: "#ec4899",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        type: 'function',
        function: {
          name: 'web_search',
          description: 'Search the web for current information. Use this when you need to find up-to-date information about any topic.',
          parameters: {
            type: 'object',
            properties: {
              query: {
                type: 'string',
                description: 'The search query'
              }
            },
            required: ['query']
          }
        },
        _config: {
          provider: properties.provider,
          max_results: properties.max_results,
          search_depth: properties.search_depth
        }
      };
      """
    }
  end

  defp tools_combiner_node do
    %{
      type: "tools_combiner",
      title: "Tools",
      description: "Combines multiple tools into an array. Right-click to add/remove inputs.",
      category: "tool",
      inputs: [
        %{name: "tool1", type: "tool"}
      ],
      outputs: [%{name: "tools", type: "tools"}],
      properties: [%{name: "input_count", default: 1}],
      size: [160, 60],
      color: "#ec4899",
      bgcolor: "#1a1a2e",
      dynamic_inputs: %{
        type: "tool",
        name_prefix: "tool",
        min: 1,
        max: 10
      },
      execute_code: """
      const tools = [];
      for (let i = 0; i < inputs.length; i++) {
        if (inputs[i] && typeof inputs[i] === 'object' && inputs[i].type === 'function') {
          tools.push(inputs[i]);
        }
      }
      return tools;
      """
    }
  end
end
