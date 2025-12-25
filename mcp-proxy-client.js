#!/usr/bin/env node

/**
 * MCP Proxy Client - Stdio Mode
 * 
 * This script acts as a proxy between MCP clients (GitHub Copilot, Claude Desktop)
 * and the Alex backend. It translates MCP calls into REST API calls with authentication.
 * 
 * Configuration:
 * - ALEX_API_URL: Alex API URL (e.g., http://alex.api.pmats.ai/api)
 * - MCP_API_KEY: API key for authentication (format: sk_live_...)
 * 
 * Architecture:
 *   GitHub Copilot/Claude Desktop → This proxy (stdio) → Alex backend API
 * 
 * Usage:
 *   node mcp-proxy-client.js
 *   Or via GitHub Copilot/Claude Desktop (launched automatically)
 * 
 * Reference:
 *   https://modelcontextprotocol.io/docs
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import fetch from "node-fetch";
import { z } from "zod";

// Configuration from environment variables
const ALEX_API_URL = process.env.ALEX_API_URL || process.env.MCP_SERVER_URL || "http://localhost:5000";
const ALEX_API_KEY = process.env.ALEX_API_KEY;
const MCP_CLIENT_NAME = process.env.MCP_CLIENT_NAME;

// Validate credentials
if (!ALEX_API_KEY) {
  console.error("❌ ERROR: Missing required environment variable");
  console.error("   ALEX_API_KEY must be set");
  console.error("");
  console.error("   Example:");
  console.error("   export ALEX_API_KEY=sk_live_xxxxx");
  process.exit(1);
}

/**
 * Detect MCP client type from environment
 * Priority:
 * 1. Explicit MCP_CLIENT_NAME variable (set by install script)
 * 2. GITHUB_COPILOT_TOKEN → github_copilot
 * 3. ANTHROPIC_API_KEY + TERM_PROGRAM=cursor → cursor
 * 4. TERM_PROGRAM=cursor → cursor
 * 5. TERM_PROGRAM=windsurf → windsurf
 * 6. VSCODE_PID → vscode
 * 7. Fallback → other
 */
function detectMCPClient() {
  // Priority 1: Explicit client name
  if (MCP_CLIENT_NAME) {
    const normalized = MCP_CLIENT_NAME.toLowerCase().replace(/[^a-z_]/g, '_');
    console.error(`🔍 Client detection: MCP_CLIENT_NAME=${normalized}`);
    return `mcp:mcp_${normalized}`;
  }

  // Priority 2: GitHub Copilot
  if (process.env.GITHUB_COPILOT_TOKEN) {
    console.error('🔍 Client detection: GitHub Copilot (GITHUB_COPILOT_TOKEN present)');
    return 'mcp:mcp_github_copilot';
  }

  // Priority 3-5: TERM_PROGRAM detection
  const termProgram = process.env.TERM_PROGRAM?.toLowerCase();
  if (termProgram) {
    if (termProgram.includes('cursor')) {
      console.error('🔍 Client detection: Cursor (TERM_PROGRAM)');
      return 'mcp:mcp_cursor';
    }
    if (termProgram.includes('windsurf')) {
      console.error('🔍 Client detection: Windsurf (TERM_PROGRAM)');
      return 'mcp:mcp_windsurf';
    }
  }

  // Priority 6: VS Code
  if (process.env.VSCODE_PID) {
    console.error('🔍 Client detection: VS Code (VSCODE_PID present)');
    return 'mcp:mcp_vscode';
  }

  // Priority 7: Claude Desktop (if ANTHROPIC_API_KEY present)
  if (process.env.ANTHROPIC_API_KEY) {
    console.error('🔍 Client detection: Claude Desktop (ANTHROPIC_API_KEY present)');
    return 'mcp:mcp_claude_desktop';
  }

  // Fallback
  console.error('🔍 Client detection: Unknown client (fallback to mcp_other)');
  return 'mcp:mcp_other';
}

const CLIENT_TYPE = detectMCPClient();

console.error(`🔗 Connecting to Alex API: ${ALEX_API_URL}`);
console.error(`🔑 API Key: ${ALEX_API_KEY.substring(0, 12)}...`);
console.error(`👤 Client Type: ${CLIENT_TYPE}`);

/**
 * Call Alex RAG API with authentication
 */
async function callAlexAPI(question, isComparison = false) {
  const endpoint = `${ALEX_API_URL}/api/chat/message`;

  console.error(`🌐 HTTP POST ${endpoint}`);
  console.error(`📝 Question: ${question?.substring(0, 100)}...`);
  console.error(`🔍 Request body:`, JSON.stringify({ message: question, conversation_id: null }));

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        "Content-Type": "application/json",
        "X-API-Key": ALEX_API_KEY,
        "X-Client-Type": CLIENT_TYPE
      },
      body: JSON.stringify({
        message: question,
        conversation_id: null // New conversation each time
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`HTTP ${response.status}: ${errorText}`);
    }

    const data = await response.json();
    console.error(`✅ Response received (${data.message?.length || 0} chars)`);
    
    return data.message || data.error || "No response from Alex API";
    
  } catch (error) {
    console.error(`❌ API call failed: ${error.message}`);
    return `ERROR: ${error.message}`;
  }
}

/**
 * Create MCP server (high-level McpServer API)
 * This server exposes Alex's tools via stdio to GitHub Copilot
 */
const server = new McpServer(
  {
    name: "alex-mcp-proxy",
    version: "0.1.0"
  },
  {
    capabilities: {
      tools: {}
    }
  }
);

/**
 * Register alex_al_query tool
 */
server.registerTool(
  "alex_al_query",
  {
    description: `✅ DEFAULT TOOL - Use for ALL Business Central AL questions (except version comparisons).

Query Alex RAG (Retrieval-Augmented Generation) for expert answers on Microsoft Dynamics 365 Business Central AL code. This tool searches through vectorized AL code documentation and provides contextual answers with code examples.

## When to Use This Tool

- When you need information about AL syntax, objects, or patterns
- When troubleshooting AL code issues or errors
- When looking for best practices in Business Central development
- When you need code examples for specific AL functionality
- When asking about table structures, pages, codeunits, or any AL object
- For general AL development questions (without version comparison)

## When NOT to Use This Tool

- For comparing different BC versions (use alex_al_comparison instead)
- For non-AL questions (use appropriate tools or standard Copilot)
- For questions about Azure, .NET, or other technologies (use microsoft_docs tools)

## Usage Pattern

Ask clear, specific questions about Business Central AL development. The tool works best when you:
1. Specify the AL object type (table, page, codeunit, etc.) when relevant
2. Include context about what you're trying to achieve
3. Mention specific AL features or functions you're interested in

## Examples

- "How do I create a table extension in AL?"
- "What's the syntax for posting a sales order in AL?"
- "Show me examples of using RecordRef in Business Central"
- "How to implement OnValidate trigger in AL?"
- "What are the best practices for error handling in AL?"

## Output Format

The tool returns markdown-formatted text with:
- Detailed explanations of AL concepts
- Code examples with syntax highlighting
- References to relevant AL objects and patterns
- Best practices and recommendations when applicable`,
    inputSchema: {
      request: z.string().describe("Your question about Business Central AL code. Be specific and provide context when possible.")
    }
  },
  async (args, extra) => {
    console.error(`🔧 Tool called: alex_al_query`);
    console.error(`📥 Args received:`, JSON.stringify(args));
    
    const request = args.request;
    console.error(`📝 Question: ${request?.substring(0, 100)}...`);

    const response = await callAlexAPI(request, false);
    return {
      content: [
        {
          type: "text",
          text: response
        }
      ]
    };
  }
);

/**
 * Register alex_al_comparison tool
 */
server.registerTool(
  "alex_al_comparison",
  {
    description: `⚠️ USE ONLY for comparing BC versions (26 vs 27, etc.). For ALL other AL questions, use alex_al_query.

Compare different versions of Business Central AL code. This specialized tool analyzes code differences between BC versions to identify breaking changes, new features, and deprecated functionality.

## When to Use This Tool

- When comparing AL code between two BC versions (e.g., BC 26 vs BC 27)
- When investigating breaking changes during BC version upgrades
- When looking for new features introduced in a specific BC version
- When tracking deprecated or obsolete AL objects across versions
- When analyzing API changes between BC releases

## When NOT to Use This Tool

- For general AL questions without version comparison (use alex_al_query instead)
- For single-version AL documentation lookup
- For questions about upgrade procedures or migration steps

## Usage Pattern

ALWAYS explicitly mention the versions you want to compare. The tool analyzes code changes at the file and element level to provide detailed version comparisons.

## Version Format

Supported BC versions: 23 through 27 and later. You can specify:
- Major version only: "BC 26" (uses latest available minor version)
- Full version: "BC 26.5" or "BC 26.5.0.0"

## Examples

- "What changed in the Sales Header table between BC 26 and BC 27?"
- "Compare the Item table between version 25 and 26"
- "Show me breaking changes in Codeunit 80 from BC 24 to BC 25"
- "What's new in the Sales Invoice page between version 26 and 27?"
- "List deprecated functions in BC 27 compared to BC 26"

## Output Format

The tool returns markdown-formatted comparison reports with:
- Side-by-side code differences
- Lists of added, modified, and removed elements
- Breaking change indicators
- Detailed change analysis
- Recommendations for handling version-specific changes`,
    inputSchema: {
      request: z.string().describe("Your comparison question. Must explicitly mention versions or indicate comparison intent.")
    }
  },
  async (args, extra) => {
    console.error(`🔧 Tool called: alex_al_comparison`);
    console.error(`📥 Args received:`, JSON.stringify(args));
    
    const request = args.request;
    console.error(`📝 Question: ${request?.substring(0, 100)}...`);

    const response = await callAlexAPI(request, true);
    return {
      content: [
        {
          type: "text",
          text: response
        }
      ]
    };
  }
);

/**
 * Start server with chosen transport
 */
async function main() {
  try {
    // Stdio mode for GitHub Copilot and Claude Desktop
    console.error("🚀 Starting MCP proxy server (stdio mode)...");
    
    const transport = new StdioServerTransport();
    await server.connect(transport);
    
    console.error("✅ Proxy server ready! Waiting for requests from MCP client...");
    
  } catch (error) {
    console.error("❌ Error starting proxy server:", error.message);
    process.exit(1);
  }
}

main();
