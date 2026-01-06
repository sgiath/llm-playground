// Litegraph Hook for Phoenix LiveView
// Initializes and manages the litegraph.js node editor

import { LiteGraph, LGraph, LGraphCanvas } from "../../vendor/litegraph";

const LitegraphHook = {
  mounted() {
    this.registeredTypes = new Set();
    this.executingNodes = new Set(); // Track currently executing nodes
    this.completedNodes = new Set(); // Track completed nodes
    this.originalColors = new Map(); // Store original node colors
    this.clearDefaultNodes();
    this.initGraph();
    this.setupResizeHandler();
    this.setupEventListeners();
    this.setupServerEventHandlers();
    this.setupExecutionEventHandlers();

    // Notify server that hook is ready to receive node type definitions
    this.pushEvent("hook_ready", {});
  },

  destroyed() {
    if (this.graph) {
      this.graph.stop();
    }
    if (this.resizeHandler) {
      window.removeEventListener("resize", this.resizeHandler);
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
  },

  // Clear all default litegraph node types to start fresh
  clearDefaultNodes() {
    Object.keys(LiteGraph.registered_node_types).forEach((type) => {
      delete LiteGraph.registered_node_types[type];
    });
    // Clear search box extras too
    LiteGraph.searchbox_extras = {};
  },

  initGraph() {
    // Configure LiteGraph global settings for better contrast
    LiteGraph.NODE_TITLE_COLOR = "#ffffff";
    LiteGraph.NODE_SELECTED_TITLE_COLOR = "#ffffff";
    LiteGraph.NODE_TEXT_COLOR = "#e0e0e0";
    
    // Modern widget styling - bigger widgets with more space
    LiteGraph.NODE_WIDGET_HEIGHT = 28;  // Increased from 20
    LiteGraph.NODE_SLOT_HEIGHT = 24;    // Slightly taller slots
    LiteGraph.NODE_TITLE_HEIGHT = 34;   // Slightly taller title
    LiteGraph.NODE_TEXT_SIZE = 14;      // Readable text size
    
    // Modern widget colors - cleaner, more contrast
    LiteGraph.WIDGET_BGCOLOR = "#1a1a2e";        // Darker, slightly blue-tinted
    LiteGraph.WIDGET_OUTLINE_COLOR = "#4a4a6a";  // Softer outline
    LiteGraph.WIDGET_TEXT_COLOR = "#f0f0f0";     // Brighter text
    LiteGraph.WIDGET_SECONDARY_TEXT_COLOR = "#a0a0b0";  // Softer secondary text
    LiteGraph.WIDGET_MARGIN = 10;                // Widget side margin
    
    // Node colors - modern dark theme
    LiteGraph.NODE_DEFAULT_COLOR = "#2d2d44";
    LiteGraph.NODE_DEFAULT_BGCOLOR = "#1e1e2e";
    LiteGraph.NODE_DEFAULT_BOXCOLOR = "#5a5a7a";

    // Create the graph
    this.graph = new LGraph();

    // Create the canvas renderer attached to our canvas element
    this.graphCanvas = new LGraphCanvas(this.el, this.graph);

    // Configure canvas options
    this.graphCanvas.background_image = null;
    this.graphCanvas.render_shadows = true;
    this.graphCanvas.render_canvas_border = false;
    this.graphCanvas.node_title_color = "#ffffff";

    // Override the prompt function to use LiveView modal
    this.setupPromptOverride();

    // Setup graph change callbacks
    this.setupGraphCallbacks();

    // Start the graph execution
    this.graph.start();

    // Initial resize to fit container
    this.resizeCanvas();

    // Push initial graph state
    this.pushGraphState("graph_initialized");
  },

  // Override LiteGraph's prompt function to use LiveView modal instead
  setupPromptOverride() {
    const hook = this;
    
    // Store reference to the original prompt method
    const originalPrompt = LGraphCanvas.prototype.prompt;
    
    // Storage for pending prompt callback
    this.pendingPromptCallback = null;
    this.pendingPromptWidget = null;
    
    // Override the prompt method
    LGraphCanvas.prototype.prompt = function(title, value, callback, event, multiline) {
      // Find the node and widget that triggered this prompt
      let nodeId = null;
      let widgetName = title;
      
      // Try multiple sources to find the node - node_widget is set too late, try node_over
      if (this.node_widget && this.node_widget[0]) {
        nodeId = this.node_widget[0].id;
        if (this.node_widget[1]) {
          widgetName = this.node_widget[1].name || title;
        }
      } else if (this.node_over) {
        // node_over is the node currently under the mouse
        nodeId = this.node_over.id;
        // Try to find the widget by matching the value
        if (this.node_over.widgets) {
          const widget = this.node_over.widgets.find(w => w.value === value || w.name === title);
          if (widget) {
            widgetName = widget.name || title;
          }
        }
      }
      
      // If we have a valid node, use LiveView modal
      if (nodeId !== null) {
        // Store the callback and widget for later
        hook.pendingPromptCallback = callback;
        hook.pendingPromptWidget = this.node_widget ? this.node_widget[1] : null;
        
        // Get the node for additional context
        const node = hook.graph.getNodeById(nodeId);
        const nodeType = node ? node.type : null;
        
        // Gather input connection info for prompt_template nodes
        let inputConnections = null;
        if (node && nodeType === "utility/prompt_template") {
          inputConnections = [];
          if (node.inputs) {
            node.inputs.forEach((input, idx) => {
              const connInfo = {
                slot: idx,
                name: input.name,
                connected: input.link !== null,
                source_node: null,
                source_title: null
              };
              
              // If connected, find the source node
              if (input.link !== null) {
                const link = hook.graph.links[input.link];
                if (link) {
                  const sourceNode = hook.graph.getNodeById(link.origin_id);
                  if (sourceNode) {
                    connInfo.source_node = sourceNode.id;
                    connInfo.source_title = sourceNode.title || sourceNode.type.split('/').pop();
                  }
                }
              }
              
              inputConnections.push(connInfo);
            });
          }
        }
        
        // Push event to LiveView to show modal
        hook.pushEvent("show_text_widget_modal", {
          node_id: nodeId,
          widget_name: widgetName,
          value: value || "",
          multiline: multiline || false,
          title: title,
          node_type: nodeType,
          input_connections: inputConnections
        });
      } else {
        // Fallback to original prompt if we can't determine the node
        originalPrompt.call(this, title, value, callback, event, multiline);
      }
    };
    
    // Handle the saved value from LiveView modal
    this.handleEvent("text_widget_value_saved", (payload) => {
      const { node_id, widget_name, value } = payload;
      
      // Call the stored callback with the new value
      if (hook.pendingPromptCallback) {
        hook.pendingPromptCallback(value);
        hook.pendingPromptCallback = null;
        hook.pendingPromptWidget = null;
      }
      
      // Also update the node property directly to ensure sync
      const node = hook.graph.getNodeById(node_id);
      if (node && node.widgets) {
        const widget = node.widgets.find(w => w.name === widget_name);
        if (widget) {
          widget.value = value;
          if (widget.property) {
            node.properties[widget.property] = value;
          }
        }
      }
      
      // Redraw the canvas
      hook.graphCanvas.setDirty(true, true);
    });
    
    // Handle modal cancel - just clear the pending callback
    this.handleEvent("text_widget_modal_cancelled", () => {
      hook.pendingPromptCallback = null;
      hook.pendingPromptWidget = null;
    });
  },

  // Handle events pushed from the server
  setupServerEventHandlers() {
    // Register a single node type from server definition
    this.handleEvent("register_node_type", (payload) => {
      this.registerNodeTypeFromDefinition(payload);
    });

    // Register multiple node types at once
    this.handleEvent("register_node_types", (payload) => {
      const { types } = payload;
      console.log(`Registering ${types.length} node types...`);
      types.forEach((def) => this.registerNodeTypeFromDefinition(def));
      console.log(
        "Registered node types:",
        Object.keys(LiteGraph.registered_node_types)
      );
    });

    // Add a node to the graph
    this.handleEvent("add_node", (payload) => {
      const { type, pos, properties } = payload;
      const node = LiteGraph.createNode(type);
      if (node) {
        if (pos) node.pos = pos;
        if (properties) {
          Object.assign(node.properties, properties);
          // Update widgets to reflect properties
          if (node.widgets) {
            node.widgets.forEach((w) => {
              if (properties[w.name] !== undefined) {
                w.value = properties[w.name];
              }
            });
          }
        }
        this.graph.add(node);
      }
    });

    // Remove a node from the graph
    this.handleEvent("remove_node", (payload) => {
      const { node_id } = payload;
      const node = this.graph.getNodeById(node_id);
      if (node) {
        this.graph.remove(node);
      }
    });

    // Connect two nodes
    this.handleEvent("connect_nodes", (payload) => {
      const { from_node_id, from_slot, to_node_id, to_slot } = payload;
      const fromNode = this.graph.getNodeById(from_node_id);
      const toNode = this.graph.getNodeById(to_node_id);
      if (fromNode && toNode) {
        fromNode.connect(from_slot, toNode, to_slot);
      }
    });

    // Load a complete graph from serialized data
    // Use setTimeout to ensure node types are registered first
    this.handleEvent("load_graph", (payload) => {
      const { graph_data } = payload;
      console.log(
        `Loading graph with ${graph_data.nodes?.length || 0} nodes...`
      );

      // Store graph data to load after registration completes
      this.pendingGraphLoad = graph_data;

      // Defer loading to allow node types registration to complete
      setTimeout(() => {
        if (this.pendingGraphLoad) {
          console.log(
            "Available node types:",
            Object.keys(LiteGraph.registered_node_types)
          );
          try {
            // graph.configure override handles _graphLoading flag
            this.graph.configure(this.pendingGraphLoad);
            // Force canvas redraw
            this.graphCanvas.setDirty(true, true);
            this.graphCanvas.draw(true, true);
            // Also resize to ensure proper rendering
            this.resizeCanvas();
            console.log(
              "Graph loaded successfully with",
              this.graph._nodes.length,
              "nodes"
            );
          } catch (e) {
            console.error("Error loading graph:", e);
          }
          this.pendingGraphLoad = null;
        }
      }, 100); // Give a bit more time for registration
    });

    // Update conversation options in all load/save conversation nodes
    this.handleEvent("update_conversation_options", (payload) => {
      const { load_values, save_values } = payload;
      console.log("Updating conversation options:", {
        load_values,
        save_values,
      });

      // Update all nodes that have conversation_id widgets
      this.graph._nodes.forEach((node) => {
        if (
          node.type === "storage/load_conversation" ||
          node.type === "storage/save_conversation"
        ) {
          const values =
            node.type === "storage/load_conversation" ? load_values : save_values;
          const propName = "conversation_id";

          // Update the combo mapping
          node["_combo_mapping_" + propName] = values;

          // Find and update the widget
          const widget = node.widgets?.find(
            (w) => w.name === "Conversation" || w.name === propName
          );
          if (widget) {
            // Update widget options with labels
            widget.options.values = values.map((opt) => opt.label);

            // If current value is not in the list, update to first option
            const currentValue = node.properties[propName];
            const found = values.find((opt) => opt.value === currentValue);
            if (!found && values.length > 0) {
              widget.value = values[0].label;
              node.properties[propName] = values[0].value;
            } else if (found) {
              widget.value = found.label;
            }
          }
        }
      });

      // Redraw the canvas
      this.graphCanvas.setDirty(true, true);
      this.graphCanvas.draw(true, true);
    });

    // Clear the graph
    this.handleEvent("clear_graph", () => {
      this.graph.clear();
    });

    // Update node property (single property)
    this.handleEvent("update_node_property", (payload) => {
      const { node_id, property, value } = payload;
      const node = this.graph.getNodeById(node_id);
      if (node) {
        node.properties[property] = value;
        // Update widget if exists
        if (node.widgets) {
          const widget = node.widgets.find((w) => w.name === property);
          if (widget) widget.value = value;
        }
        this.graphCanvas.setDirty(true, true);
      }
    });

    // Update multiple node properties at once (for stateful nodes)
    this.handleEvent("update_node_properties", (payload) => {
      const { node_id, properties } = payload;
      const node = this.graph.getNodeById(node_id);
      if (node) {
        // Update all properties
        Object.entries(properties).forEach(([key, value]) => {
          node.properties[key] = value;
          // Update widget if exists
          if (node.widgets) {
            const widget = node.widgets.find(
              (w) => w.property === key || w.name === key
            );
            if (widget) widget.value = value;
          }
        });
        this.graphCanvas.setDirty(true, true);
        // Trigger graph save
        this.pushGraphState("node_properties_updated");
      }
    });
  },

  // Handle execution-related events from the server
  setupExecutionEventHandlers() {
    // Initialize streaming content storage
    this.streamingContent = new Map(); // node_id -> accumulated content
    // Track if we're in preview mode (no visual highlighting)
    this._previewMode = false;

    // Server requests current graph for execution
    this.handleEvent("request_execution", () => {
      // Reset execution state before starting new execution
      // This ensures all nodes start with their default colors
      this.resetExecutionState();
      // Clear any previous streaming content
      this.streamingContent.clear();
      // Full execution mode - enable highlighting
      this._previewMode = false;
      const graphData = this.graph.serialize();
      this.pushEvent("execute_workflow", { graph: graphData });
    });

    // Server requests current graph for preview execution
    this.handleEvent("request_preview", () => {
      // Preview mode - no visual highlighting
      this._previewMode = true;
      const graphData = this.graph.serialize();
      this.pushEvent("execute_preview", { graph: graphData });
    });

    // Node is starting execution - highlight it (unless in preview mode)
    this.handleEvent("node_executing", (payload) => {
      // Skip highlighting in preview mode
      if (this._previewMode) return;

      const { node_id } = payload;
      const node = this.graph.getNodeById(node_id);
      if (node) {
        // Store original colors if not already stored
        if (!this.originalColors.has(node_id)) {
          this.originalColors.set(node_id, {
            color: node.color,
            bgcolor: node.bgcolor,
          });
        }

        // Mark as executing
        this.executingNodes.add(node_id);

        // Initialize streaming content for this node
        this.streamingContent.set(node_id, "");

        // Set executing visual style (pulsing yellow/orange)
        node.color = "#f59e0b";
        node.bgcolor = "#78350f";

        // Add custom drawing for execution indicator
        this.setupNodeExecutionDrawing(node);

        this.graphCanvas.setDirty(true, true);
      }
    });

    // Streaming delta from Agent nodes - update display in real-time
    this.handleEvent("stream_delta", (payload) => {
      const { node_id, content } = payload;

      // Accumulate streaming content
      const currentContent = this.streamingContent.get(node_id) || "";
      const newContent = currentContent + (content || "");
      this.streamingContent.set(node_id, newContent);

      // Find connected Display nodes and update them
      this.updateConnectedDisplayNodes(node_id, newContent);
    });

    // Node has completed execution
    this.handleEvent("node_completed", (payload) => {
      const { node_id, output } = payload;
      const node = this.graph.getNodeById(node_id);
      if (node) {
        // Skip visual highlighting in preview mode
        if (!this._previewMode) {
          // Remove from executing, add to completed
          this.executingNodes.delete(node_id);
          this.completedNodes.add(node_id);

          // Set completed visual style (green)
          node.color = "#22c55e";
          node.bgcolor = "#14532d";
        }

        // Update connected Display nodes with final output
        if (output !== null && output !== undefined) {
          this.updateConnectedDisplayNodes(node_id, output);
        }

        // Also update the node's own display if it's a Display node
        if (
          node.type === "output/display" &&
          output !== null &&
          output !== undefined
        ) {
          node.properties.value = output;
        }

        this.graphCanvas.setDirty(true, true);
      }
    });

    // Tool node is starting execution - highlight it (unless in preview mode)
    this.handleEvent("tool_executing", (payload) => {
      // Skip highlighting in preview mode
      if (this._previewMode) return;

      const { node_id } = payload;
      const node = this.graph.getNodeById(node_id);
      if (node) {
        // Store original colors if not already stored
        if (!this.originalColors.has(node_id)) {
          this.originalColors.set(node_id, {
            color: node.color,
            bgcolor: node.bgcolor,
          });
        }

        // Mark as executing
        this.executingNodes.add(node_id);

        // Set executing visual style (pulsing yellow/orange)
        node.color = "#f59e0b";
        node.bgcolor = "#78350f";

        // Add custom drawing for execution indicator
        this.setupNodeExecutionDrawing(node);

        this.graphCanvas.setDirty(true, true);
      }
    });

    // Tool node has completed execution
    this.handleEvent("tool_completed", (payload) => {
      const { node_id } = payload;
      const node = this.graph.getNodeById(node_id);
      if (node) {
        // Skip visual highlighting in preview mode
        if (!this._previewMode) {
          // Remove from executing, add to completed
          this.executingNodes.delete(node_id);
          this.completedNodes.add(node_id);

          // Set completed visual style (green)
          node.color = "#22c55e";
          node.bgcolor = "#14532d";
        }

        this.graphCanvas.setDirty(true, true);
      }
    });

    // Node error occurred
    this.handleEvent("node_error", (payload) => {
      const { node_id, reason } = payload;
      console.error(`Node ${node_id} error:`, reason);

      const node = this.graph.getNodeById(node_id);
      if (node) {
        // Remove from executing
        this.executingNodes.delete(node_id);

        // Set error visual style (red)
        node.color = "#ef4444";
        node.bgcolor = "#7f1d1d";

        // Store error message on the node for display
        node.properties._error = reason;

        this.graphCanvas.setDirty(true, true);
      }
    });

    // Entire execution is complete
    this.handleEvent("execution_complete", () => {
      console.log("Workflow execution complete");
      // Keep nodes green to show successful execution
      // Execution state will be reset when:
      // 1. User changes a node's config (widget value)
      // 2. A new execution starts
    });

    // Execution error occurred
    this.handleEvent("execution_error", (payload) => {
      console.error("Workflow execution error:", payload.reason);
      this.resetExecutionState();
    });

    // Clear message input textareas
    this.handleEvent("clear_message_inputs", () => {
      // Find all message input textareas and clear them
      document
        .querySelectorAll('textarea[id^="message-input-"]')
        .forEach((textarea) => {
          textarea.value = "";
        });
    });
  },

  // Update Display nodes connected to a source node's output
  updateConnectedDisplayNodes(sourceNodeId, content) {
    // Find all links from this node
    const links = this.graph.links;
    if (!links) return;

    for (const linkId in links) {
      const link = links[linkId];
      if (!link) continue;

      // Link format: { id, type, origin_id, origin_slot, target_id, target_slot }
      if (link.origin_id === sourceNodeId) {
        const targetNode = this.graph.getNodeById(link.target_id);
        if (targetNode && targetNode.type === "output/display") {
          // Update the Display node's value property
          targetNode.properties.value = content;
          this.graphCanvas.setDirty(true, true);
        }

        // Also check if target is an Agent node - update its response display
        if (
          targetNode &&
          (targetNode.type === "agent/stateless_agent" ||
            targetNode.type === "agent/stateful_agent")
        ) {
          targetNode.properties._last_response = content;
        }
      }
    }
  },

  // Setup custom drawing for nodes during execution
  setupNodeExecutionDrawing(node) {
    const originalDrawForeground = node.onDrawForeground?.bind(node);

    node.onDrawForeground = (ctx) => {
      // Call original if exists
      if (originalDrawForeground) {
        originalDrawForeground(ctx);
      }

      // Draw pulsing border for executing nodes
      if (this.executingNodes.has(node.id)) {
        const time = Date.now() / 300;
        const pulse = 0.5 + 0.5 * Math.sin(time);
        ctx.strokeStyle = `rgba(245, 158, 11, ${0.5 + 0.5 * pulse})`;
        ctx.lineWidth = 3;
        ctx.strokeRect(-3, -3, node.size[0] + 6, node.size[1] + 6);
      }
    };
  },

  // Reset all nodes to their original state
  resetExecutionState() {
    // Restore original colors for all affected nodes
    for (const [node_id, colors] of this.originalColors) {
      const node = this.graph.getNodeById(node_id);
      if (node) {
        node.color = colors.color;
        node.bgcolor = colors.bgcolor;
      }
    }

    // Clear tracking sets
    this.executingNodes.clear();
    this.completedNodes.clear();
    this.originalColors.clear();

    this.graphCanvas.setDirty(true, true);
  },

  // Register a node type from a server-provided definition
  registerNodeTypeFromDefinition(def) {
    const {
      type,
      title,
      description,
      category,
      inputs,
      outputs,
      properties,
      widgets,
      size,
      color,
      bgcolor,
      execute_code,
      display_value,
      dynamic_inputs,
      hide_widget_on_input,
      resizable,
    } = def;

    // Skip if already registered
    if (this.registeredTypes.has(type)) {
      console.log(`Node type ${type} already registered, skipping`);
      return;
    }

    const hook = this;

    // Create the node constructor function
    function DynamicNode() {
      // Add inputs
      if (inputs) {
        inputs.forEach((input) => {
          this.addInput(input.name, input.type || null);
        });
      }

      // Add outputs
      if (outputs) {
        outputs.forEach((output) => {
          this.addOutput(output.name, output.type || null);
        });
      }

      // Add properties with default values
      if (properties) {
        properties.forEach((prop) => {
          this.addProperty(prop.name, prop.default);
        });
      }

      // Store dynamic inputs config on the node instance
      if (dynamic_inputs) {
        this._dynamic_inputs = dynamic_inputs;
      }

      // Store hide_widget_on_input mapping for dynamic widget visibility
      if (hide_widget_on_input) {
        this._hide_widget_on_input = hide_widget_on_input;
      }

      // Add widgets
      if (widgets) {
        widgets.forEach((w) => {
          if (w.type === "button") {
            // Special handling for button widgets
            const buttonCallback = () => {
              // Handle special callbacks
              if (w.callback === "clearConversationHistory") {
                // Clear the conversation history
                this.properties.conversation_history = [];
                // Notify server of property change
                hook.pushEvent("property_changed", {
                  node_id: this.id,
                  property: "conversation_history",
                  value: [],
                });
                // Save graph state to database
                hook.pushGraphState("property_changed");
                console.log(`Cleared conversation history for node ${this.id}`);
              } else if (w.callback === "saveConversation") {
                // Manual save conversation to database
                const nodeId = this.id;
                
                // Check if conversation input (slot 1) is connected and has a value
                let conversationId = this.properties.conversation_id || "__new__";
                if (this.inputs && this.inputs[1] && this.inputs[1].link !== null) {
                  // Get the connected value from the link
                  const link = hook.graph.links[this.inputs[1].link];
                  if (link) {
                    const sourceNode = hook.graph.getNodeById(link.origin_id);
                    if (sourceNode && sourceNode.outputs && sourceNode.outputs[link.origin_slot]) {
                      const connectedValue = sourceNode.getOutputData(link.origin_slot);
                      if (connectedValue) {
                        conversationId = connectedValue;
                      }
                    }
                  }
                }
                
                const newName = this.properties.new_name || "New Conversation";
                const mode = this.properties.mode || "override";

                // Send save request to server
                hook.pushEvent("save_conversation_manual", {
                  node_id: nodeId,
                  conversation_id: conversationId,
                  new_name: newName,
                  mode: mode,
                });
                console.log(
                  `Manual save conversation triggered for node ${nodeId}`
                );
              } else if (w.callback === "editConversation") {
                // Navigate to conversation editor
                const conversationId = this.properties.conversation_id;
                if (conversationId && conversationId !== "__new__") {
                  window.location.href = `/conv/${conversationId}`;
                } else {
                  console.warn("No conversation selected to edit");
                }
              }
            };
            this.addWidget(
              "button",
              w.name,
              null,
              buttonCallback,
              w.options || {}
            );
          } else {
            const callback = (v) => {
              // For combo widgets with value/label pairs, v is the label
              // We need to find the actual value
              let actualValue = v;
              if (w.type === "combo" && w.options && w.options.values) {
                const values = w.options.values;
                if (
                  values.length > 0 &&
                  typeof values[0] === "object" &&
                  values[0].label
                ) {
                  const found = values.find((opt) => opt.label === v);
                  if (found) {
                    actualValue = found.value;
                  }
                }
              }

              this.properties[w.property || w.name] = actualValue;
              // Notify server of property change
              hook.pushEvent("property_changed", {
                node_id: this.id,
                property: w.property || w.name,
                value: actualValue,
              });
              // Save graph state to database
              hook.pushGraphState("property_changed");
            };

            // Transform options for combo widgets with value/label pairs
            let widgetOptions = w.options || {};
            if (w.type === "combo" && widgetOptions.values) {
              const values = widgetOptions.values;
              if (
                values.length > 0 &&
                typeof values[0] === "object" &&
                values[0].label
              ) {
                // Convert to array of labels for display
                widgetOptions = {
                  ...widgetOptions,
                  values: values.map((opt) => opt.label),
                };
                // Store the original mapping for lookup
                this["_combo_mapping_" + (w.property || w.name)] = values;
              }
            }

            // Get display value (label) for combo with value/label pairs
            let defaultValue = w.default;
            if (w.type === "combo" && w.options && w.options.values) {
              const values = w.options.values;
              if (
                values.length > 0 &&
                typeof values[0] === "object" &&
                values[0].label
              ) {
                const found = values.find((opt) => opt.value === w.default);
                if (found) {
                  defaultValue = found.label;
                } else if (values.length > 0) {
                  defaultValue = values[0].label;
                }
              }
            }

            this.addWidget(
              w.type,
              w.name,
              defaultValue,
              callback,
              widgetOptions
            );
          }
        });
      }

      // Set size
      if (size) {
        this.size = size;
      }

      // Set colors
      if (color) this.color = color;
      if (bgcolor) this.bgcolor = bgcolor;

      // Set resizable
      if (resizable) {
        this.resizable = true;
      }
    }

    // Set static properties
    DynamicNode.title = title || type.split("/").pop();
    DynamicNode.desc = description || "";

    // Store widget definitions for syncing on load
    DynamicNode.prototype._widget_defs = widgets || [];

    // Sync widget values from properties (called after configure restores properties)
    DynamicNode.prototype.syncWidgetsFromProperties = function () {
      if (!this.widgets || !this._widget_defs) return;

      this._widget_defs.forEach((wDef) => {
        const propName = wDef.property || wDef.name;
        const widget = this.widgets.find((w) => w.name === wDef.name);
        if (widget && this.properties[propName] !== undefined) {
          let displayValue = this.properties[propName];

          // For combo widgets with value/label pairs, convert value to label
          const mapping = this["_combo_mapping_" + propName];
          if (mapping && Array.isArray(mapping)) {
            const found = mapping.find((opt) => opt.value === displayValue);
            if (found) {
              displayValue = found.label;
            }
          }

          widget.value = displayValue;
        }
      });
    };

    // Add context menu options for dynamic inputs
    if (dynamic_inputs) {
      DynamicNode.prototype.getExtraMenuOptions = function (canvas, options) {
        const config = this._dynamic_inputs;
        if (!config) return;

        const currentCount = this.inputs ? this.inputs.length : 0;
        // Generate readable label from prefix (e.g., "msg" -> "Message", "tool" -> "Tool")
        const inputLabel =
          config.name_prefix.charAt(0).toUpperCase() +
          config.name_prefix
            .slice(1)
            .replace(/([A-Z])/g, " $1")
            .trim();

        // Add "Add Input" option
        if (currentCount < config.max) {
          options.push({
            content: `Add ${inputLabel} Input`,
            callback: () => {
              // Account for start_slot offset when naming dynamic inputs
              const dynamicCount = currentCount - (config.start_slot || 0);
              const newIndex = dynamicCount + 1;
              const newName = `${config.name_prefix}${newIndex}`;
              this.addInput(newName, config.type || null);
              this.properties.input_count = newIndex;
              // Adjust node size based on total inputs
              const newTotalCount = currentCount + 1;
              this.size[1] = Math.max(60, 30 + newTotalCount * 25);
              this.setDirtyCanvas(true, true);
            },
          });
        }

        // Add "Remove Input" option
        // Only allow removing if we have more than the minimum dynamic inputs
        const dynamicInputCount = currentCount - (config.start_slot || 0);
        if (dynamicInputCount > config.min) {
          options.push({
            content: `Remove ${inputLabel} Input`,
            callback: () => {
              this.removeInput(currentCount - 1);
              const newDynamicCount = dynamicInputCount - 1;
              this.properties.input_count = newDynamicCount;
              // Adjust node size based on total inputs
              const newTotalCount = currentCount - 1;
              this.size[1] = Math.max(60, 30 + newTotalCount * 25);
              this.setDirtyCanvas(true, true);
            },
          });
        }
      };

      // Handle auto-add: when last input is connected, add a new one
      DynamicNode.prototype.onConnectionsChange = function (
        connectionType,
        slotIndex,
        isConnected,
        link,
        ioSlot
      ) {
        const config = this._dynamic_inputs;
        if (!config || !config.auto_add) return;

        // Skip auto-add during graph loading (global flag set before graph.configure)
        if (hook._graphLoading) return;

        // Only handle input connections (connectionType === 1 is INPUT in LiteGraph)
        if (connectionType !== 1) return;

        const currentCount = this.inputs ? this.inputs.length : 0;

        // If a connection was made and it's the last input slot
        if (isConnected && slotIndex === currentCount - 1) {
          // Check if we can add more inputs
          if (currentCount < config.max) {
            // Account for start_slot offset when naming dynamic inputs
            const dynamicCount = currentCount - (config.start_slot || 0);
            const newIndex = dynamicCount + 1;
            const newName = `${config.name_prefix}${newIndex}`;
            this.addInput(newName, config.type || null);
            this.properties.input_count = newIndex;
            // Adjust node size based on total inputs
            const newTotalCount = currentCount + 1;
            this.size[1] = Math.max(60, 30 + newTotalCount * 25);
            this.setDirtyCanvas(true, true);
          }
        }
      };

      // Restore dynamic inputs when loading from saved graph
      DynamicNode.prototype.onConfigure = function (data) {
        // Sync widgets with restored properties
        this.syncWidgetsFromProperties();

        const config = this._dynamic_inputs;
        if (!config) return;

        // The saved data includes the inputs array, so we need to ensure
        // the inputs match what was saved (litegraph handles this automatically)
        // but we need to update the size based on input count
        const inputCount = this.inputs ? this.inputs.length : 1;
        // input_count tracks only dynamic inputs (accounting for start_slot offset)
        this.properties.input_count = inputCount - (config.start_slot || 0);
        this.size[1] = Math.max(60, 30 + inputCount * 25);
      };
    } else {
      // For nodes without dynamic inputs, still need to sync widgets on configure
      DynamicNode.prototype.onConfigure = function (data) {
        this.syncWidgetsFromProperties();
      };
    }

    // Helper function to update widget visibility based on connected inputs
    // Since this version of LiteGraph doesn't support widget.hidden, we remove/add widgets
    const updateWidgetVisibility = function (node) {
      if (!node._hide_widget_on_input || !node.inputs) return;

      // Initialize storage for removed widgets if not exists
      if (!node._removed_widgets) {
        node._removed_widgets = {};
      }

      const mapping = node._hide_widget_on_input;
      let changed = false;

      for (const [inputName, widgetNames] of Object.entries(mapping)) {
        // Find the input slot index by name
        const inputIndex = node.inputs.findIndex(
          (inp) => inp.name === inputName
        );
        if (inputIndex === -1) continue;

        // Check if this input has a connection
        const isConnected = node.inputs[inputIndex].link !== null;

        // Support both single widget name (string) and array of widget names
        const widgetNameList = Array.isArray(widgetNames) ? widgetNames : [widgetNames];

        for (const widgetName of widgetNameList) {
          // Check if widget currently exists
          const widgetIndex = node.widgets
            ? node.widgets.findIndex((w) => w.name === widgetName)
            : -1;
          const widgetExists = widgetIndex !== -1;
          const wasRemoved = node._removed_widgets[widgetName] !== undefined;

          if (isConnected && widgetExists) {
            // Remove the widget - store it first
            const widget = node.widgets[widgetIndex];
            node._removed_widgets[widgetName] = {
              widget: widget,
              index: widgetIndex,
            };
            node.widgets.splice(widgetIndex, 1);
            changed = true;
          } else if (!isConnected && wasRemoved) {
            // Restore the widget
            const stored = node._removed_widgets[widgetName];
            if (stored && stored.widget) {
              // Insert at original position or at end
              const insertIndex = Math.min(
                stored.index,
                node.widgets ? node.widgets.length : 0
              );
              if (!node.widgets) node.widgets = [];
              node.widgets.splice(insertIndex, 0, stored.widget);
              delete node._removed_widgets[widgetName];
              changed = true;
            }
          }
        }
      }

      // Force node to redraw and recalculate size
      if (changed && node.graph) {
        node.setSize(node.computeSize());
        node.setDirtyCanvas(true, true);
      }
    };

    // Add onConnectionsChange to handle widget visibility
    // Must combine with existing dynamic_inputs handler if both are present
    if (hide_widget_on_input) {
      const existingConnectionsChange = DynamicNode.prototype.onConnectionsChange;
      
      DynamicNode.prototype.onConnectionsChange = function (
        connectionType,
        slotIndex,
        isConnected,
        link,
        ioSlot
      ) {
        // Call existing handler first (for dynamic_inputs auto-add)
        if (existingConnectionsChange) {
          existingConnectionsChange.call(this, connectionType, slotIndex, isConnected, link, ioSlot);
        }
        // Then update widget visibility
        updateWidgetVisibility(this);
      };

      // Also check on configure (when loading saved graph)
      const originalOnConfigure = DynamicNode.prototype.onConfigure;
      DynamicNode.prototype.onConfigure = function (data) {
        if (originalOnConfigure) {
          originalOnConfigure.call(this, data);
        }
        // Delay slightly to ensure connections are set up
        setTimeout(() => updateWidgetVisibility(this), 50);
      };

      // Check after node is added to graph
      DynamicNode.prototype.onAdded = function () {
        setTimeout(() => updateWidgetVisibility(this), 0);
      };
    }

    // Create onExecute if execute_code is provided
    if (execute_code) {
      // execute_code should be a string that returns the output mapping
      // e.g., "{ 0: inputs[0] + inputs[1] }" for an add node
      try {
        DynamicNode.prototype.onExecute = new Function(`
          const inputs = [];
          for (let i = 0; i < (this.inputs?.length || 0); i++) {
            inputs.push(this.getInputData(i));
          }
          const properties = this.properties;
          const result = (function() { ${execute_code} }).call(this);
          if (result !== undefined) {
            if (typeof result === 'object' && result !== null) {
              Object.keys(result).forEach(k => {
                this.setOutputData(parseInt(k), result[k]);
              });
            } else {
              this.setOutputData(0, result);
            }
          }
        `);
      } catch (e) {
        console.error(`Error creating onExecute for ${type}:`, e);
      }
    }

    // Create onDrawForeground if display_value is enabled
    if (display_value) {
      DynamicNode.prototype.onDrawForeground = function (ctx) {
        const prop = display_value.property || "value";
        const value = this.properties[prop];
        const font = display_value.font || "14px monospace";
        ctx.font = font;
        ctx.fillStyle = display_value.color || "#FFF";
        ctx.textAlign = "left";

        const displayText =
          typeof value === "number" ? value.toFixed(2) : String(value ?? "");

        // Calculate available width (with padding)
        const padding = 10;
        const maxWidth = this.size[0] - padding * 2;
        const lineHeight = parseInt(font) * 1.4 || 20;
        const startY = 30; // Below the title bar

        // Wrap text to fit within the node width
        const wrapText = (text, maxWidth) => {
          const lines = [];
          // First split by explicit newlines
          const paragraphs = text.split("\n");

          for (const paragraph of paragraphs) {
            if (!paragraph) {
              lines.push("");
              continue;
            }

            const words = paragraph.split(" ");
            let currentLine = "";

            for (const word of words) {
              const testLine = currentLine ? currentLine + " " + word : word;
              const metrics = ctx.measureText(testLine);

              if (metrics.width > maxWidth && currentLine) {
                lines.push(currentLine);
                currentLine = word;
              } else {
                currentLine = testLine;
              }
            }
            if (currentLine) {
              lines.push(currentLine);
            }
          }

          return lines;
        };

        const lines = wrapText(displayText, maxWidth);

        // Calculate required height
        const titleHeight = 30;
        const inputHeight = this.inputs ? this.inputs.length * 20 : 0;
        const contentHeight = lines.length * lineHeight;
        const minHeight = Math.max(
          80,
          titleHeight + inputHeight + contentHeight + padding * 2
        );

        // Resize node if needed
        if (Math.abs(this.size[1] - minHeight) > 5) {
          this.size[1] = minHeight;
          this.setDirtyCanvas(true, true);
        }

        // Draw each line
        lines.forEach((line, index) => {
          const y = startY + (index + 1) * lineHeight;
          ctx.fillText(line, padding, y);
        });
      };
    }

    // Register the node type
    const fullType = category ? `${category}/${type}` : type;
    LiteGraph.registerNodeType(fullType, DynamicNode);
    this.registeredTypes.add(type);

    console.log(`Registered node type: ${fullType}`);
  },

  // Setup callbacks on the graph to detect changes
  setupGraphCallbacks() {
    const hook = this;

    // Node added
    this.graph.onNodeAdded = (node) => {
      hook.pushEvent("node_added", {
        node_id: node.id,
        type: node.type,
        title: node.title,
        pos: node.pos,
        properties: node.properties,
      });
      hook.pushGraphState("node_added");
    };

    // Node removed
    this.graph.onNodeRemoved = (node) => {
      hook.pushEvent("node_removed", {
        node_id: node.id,
        type: node.type,
        title: node.title,
      });
      hook.pushGraphState("node_removed");
    };

    // Connection change (link added or removed)
    this.graph.onNodeConnectionChange = (
      changeType,
      node,
      slot,
      targetNode,
      targetSlot
    ) => {
      // changeType: LiteGraph.INPUT (1) or LiteGraph.OUTPUT (2)
      hook.pushEvent("connection_changed", {
        change_type: changeType === 1 ? "input" : "output",
        node_id: node.id,
        slot: slot,
        target_node_id: targetNode?.id,
        target_slot: targetSlot,
      });
      hook.pushGraphState("connection_changed");
    };

    // Override configure to detect when graph is loaded
    const originalConfigure = this.graph.configure.bind(this.graph);
    this.graph.configure = (data) => {
      // Set global loading flag to prevent auto-add during graph restore
      const wasLoading = hook._graphLoading;
      hook._graphLoading = true;
      try {
        originalConfigure(data);
      } finally {
        // Restore previous state (in case of nested calls)
        hook._graphLoading = wasLoading;
      }
      hook.pushEvent("graph_loaded", { node_count: hook.graph._nodes.length });
      hook.pushGraphState("graph_loaded");
    };
  },

  // Setup canvas event listeners for node interactions
  setupEventListeners() {
    const hook = this;

    // Track node position changes (drag end)
    this.graphCanvas.onNodeMoved = (node) => {
      hook.pushEvent("node_moved", {
        node_id: node.id,
        pos: node.pos,
      });
      hook.pushGraphState("node_moved");
    };

    // Track node selection - send full node details for sidebar
    this.graphCanvas.onNodeSelected = (node) => {
      if (!node) {
        hook.pushEvent("node_selected", { node_id: null });
        return;
      }

      // Collect inputs with connection info
      const inputs =
        node.inputs?.map((inp, i) => ({
          name: inp.name,
          type: inp.type,
          slot: i,
          connected: inp.link !== null,
          link_id: inp.link,
        })) || [];

      // Collect outputs with connection info
      const outputs =
        node.outputs?.map((out, i) => ({
          name: out.name,
          type: out.type,
          slot: i,
          connected: out.links && out.links.length > 0,
          connection_count: out.links?.length || 0,
        })) || [];

      // Collect ALL properties including internal state
      const properties = { ...node.properties };

      // Get node type info from registered types
      const nodeTypeDef = LiteGraph.registered_node_types[node.type];
      const description = nodeTypeDef?.desc || "";

      hook.pushEvent("node_selected", {
        node_id: node.id,
        type: node.type,
        title: node.title,
        description: description,
        category: node.type.split("/")[0] || "",
        inputs: inputs,
        outputs: outputs,
        properties: properties,
        size: node.size,
        color: node.color,
        bgcolor: node.bgcolor,
        pos: node.pos,
      });
    };

    // Track node deselection
    this.graphCanvas.onNodeDeselected = (node) => {
      hook.pushEvent("node_deselected", {
        node_id: node?.id,
      });
    };

    // Track property changes via widget interaction
    this.graphCanvas.onWidgetChanged = (
      name,
      value,
      oldValue,
      widget,
      node
    ) => {
      // If this node was in completed or executing state, reset its color
      // This indicates that the new config hasn't been tested yet
      if (
        hook.completedNodes.has(node.id) ||
        hook.executingNodes.has(node.id)
      ) {
        const original = hook.originalColors.get(node.id);
        if (original) {
          node.color = original.color;
          node.bgcolor = original.bgcolor;
          hook.completedNodes.delete(node.id);
          hook.executingNodes.delete(node.id);
          hook.originalColors.delete(node.id);
          hook.graphCanvas.setDirty(true, true);
        }
      }

      hook.pushEvent("property_changed", {
        node_id: node.id,
        property: name,
        value: value,
        old_value: oldValue,
      });
      hook.pushGraphState("property_changed");
    };
  },

  // Push the full serialized graph state to LiveView
  // Temporarily restores original colors before serialization to avoid saving execution state
  pushGraphState(trigger) {
    // Temporarily restore original colors before serialization
    const executionColors = new Map();
    for (const [node_id, colors] of this.originalColors) {
      const node = this.graph.getNodeById(node_id);
      if (node) {
        // Store current execution colors
        executionColors.set(node_id, {
          color: node.color,
          bgcolor: node.bgcolor,
        });
        // Restore original colors for serialization
        node.color = colors.color;
        node.bgcolor = colors.bgcolor;
      }
    }

    const graphData = this.graph.serialize();

    // Restore execution colors after serialization
    for (const [node_id, colors] of executionColors) {
      const node = this.graph.getNodeById(node_id);
      if (node) {
        node.color = colors.color;
        node.bgcolor = colors.bgcolor;
      }
    }

    this.pushEvent("graph_state_changed", {
      trigger: trigger,
      graph: graphData,
    });
  },

  setupResizeHandler() {
    this.resizeHandler = () => this.resizeCanvas();
    window.addEventListener("resize", this.resizeHandler);

    // Also observe the container for size changes (e.g., when sidebar appears/disappears)
    const container = this.el.parentElement;
    if (container && typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(() => {
        this.resizeCanvas();
      });
      this.resizeObserver.observe(container);
    }
  },

  resizeCanvas() {
    if (!this.el || !this.graphCanvas) return;

    const container = this.el.parentElement;
    if (container) {
      this.el.width = container.clientWidth;
      this.el.height = container.clientHeight;
      this.graphCanvas.resize(this.el.width, this.el.height);
      this.graphCanvas.setDirty(true, true);
    }
  },
};

export { LitegraphHook };
