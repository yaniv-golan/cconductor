// Dashboard JavaScript - Real-time metrics
class Dashboard {
    constructor() {
        this.updateInterval = 3000; // 3 seconds
        this.expandedJournalTasks = new Set(); // Track expanded journal entry breakdowns
        this.expandedJournalTools = new Set(); // Track expanded journal tools sections
        this.knownTaskIds = new Set(); // Track tasks (legacy renderTasks compatibility)
        this.newTaskIds = new Set(); // Track new tasks (legacy renderTasks compatibility)
        this.runtimeInterval = null; // Track runtime interval to avoid duplicates
        this.sessionStartTime = null; // Cache session start time
    }

    async init() {
        await this.loadAndRender();
        setInterval(() => this.loadAndRender(), this.updateInterval);
    }

    async loadAndRender() {
        try {
            const [metrics, events, session] = await Promise.all([
                this.fetchJSON('dashboard-metrics.json'),
                this.fetchJSONL('events.jsonl'),
                this.fetchJSON('session.json')
            ]);

            // Store metrics for use in journal rendering (completion messages)
            this.currentMetrics = metrics;

            this.renderHeader(session);
            this.renderStats(metrics);
            // Task Queue panel removed - tasks now shown inline in journal entries
            // this.renderTasks(tasks);
            this.renderObservations(metrics?.system_health?.observations || []);
            this.renderToolCalls(events || []);
            
            // Render journal view
            this.renderJournal(events || []);
        } catch (error) {
            console.error('Error loading data:', error);
        }
    }

    async fetchJSON(file) {
        try {
            // Use multiple cache-busting techniques for file:// protocol
            const cacheBuster = `t=${Date.now()}&r=${Math.random()}`;
            const response = await fetch(`${file}?${cacheBuster}`, {
                cache: 'no-store',
                headers: {
                    'Cache-Control': 'no-cache, no-store, must-revalidate',
                    'Pragma': 'no-cache'
                }
            });
            if (!response.ok) {
                console.warn(`[Dashboard] Failed to fetch ${file}: ${response.status}`);
                return null;
            }
            return response.json();
        } catch (error) {
            console.error(`[Dashboard] Error fetching ${file}:`, error);
            return null;
        }
    }

    async fetchJSONL(file) {
        try {
            // Use multiple cache-busting techniques for file:// protocol
            const cacheBuster = `t=${Date.now()}&r=${Math.random()}`;
            const response = await fetch(`${file}?${cacheBuster}`, {
                cache: 'no-store',
                headers: {
                    'Cache-Control': 'no-cache, no-store, must-revalidate',
                    'Pragma': 'no-cache'
                }
            });
            if (!response.ok) {
                console.warn(`[Dashboard] Failed to fetch ${file}: ${response.status}`);
                return [];
            }
            const text = await response.text();
            
            const lines = text.trim().split('\n').filter(line => line.trim());
            const parsed = [];
            let corruptedCount = 0;
            
            // Parse line-by-line, skip corrupted lines instead of failing entirely
            lines.forEach((line, index) => {
                try {
                    parsed.push(JSON.parse(line));
                } catch (error) {
                    corruptedCount++;
                    console.warn(`Corrupted JSONL line ${index + 1} in ${file}:`, line.substring(0, 100), error);
                }
            });
            
            // Show warning banner if corruption detected
            if (corruptedCount > 0) {
                this.showCorruptionWarning(file, corruptedCount, lines.length);
            }
            
            return parsed;
        } catch (error) {
            console.error(`Error fetching ${file}:`, error);
            return [];
        }
    }
    
    showCorruptionWarning(file, corruptedCount, totalLines) {
        const warningId = 'jsonl-corruption-warning';
        let warning = document.getElementById(warningId);
        
        if (!warning) {
            warning = document.createElement('div');
            warning.id = warningId;
            warning.style.cssText = `
                position: fixed;
                top: 20px;
                right: 20px;
                background: #fbbf24;
                color: #92400e;
                padding: 15px 20px;
                border-radius: 8px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.3);
                z-index: 9999;
                max-width: 400px;
                font-size: 13px;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            `;
            document.body.appendChild(warning);
        }
        
        warning.innerHTML = `
            <strong>⚠️ Data Corruption Detected</strong><br>
            ${corruptedCount} of ${totalLines} events in ${file} are corrupted.<br>
            <span style="font-size: 11px; opacity: 0.8;">Showing ${totalLines - corruptedCount} valid events.</span>
        `;
    }

    renderHeader(session) {
        if (!session) return;

        // Display research question
        const questionElement = document.getElementById('research-question');
        const questionText = session.research_question || 'Loading...';
        questionElement.textContent = questionText;

        // Setup expand/collapse for long questions
        this.setupQuestionToggle(questionText);

        // Display session ID from URL parameter if available
        const urlParams = new URLSearchParams(window.location.search);
        const sessionId = urlParams.get('session');
        if (sessionId) {
            // Add session ID as a subtitle (create element if it doesn't exist)
            let sessionIdElement = document.getElementById('session-id-display');
            if (!sessionIdElement) {
                sessionIdElement = document.createElement('div');
                sessionIdElement.id = 'session-id-display';
                sessionIdElement.style.fontSize = '0.85em';
                sessionIdElement.style.opacity = '0.7';
                sessionIdElement.style.marginTop = '5px';
                questionElement.parentNode.appendChild(sessionIdElement);
            }
            sessionIdElement.textContent = `Session: ${sessionId}`;
        }

        // Show completion banner if research is complete
        this.renderCompletionStatus(session);

        // Start live runtime counter (only once, not on every refresh)
        if (session.created_at && !this.sessionStartTime) {
            this.sessionStartTime = session.created_at;
            this.startLiveRuntime(session.created_at);
        }
    }

    setupQuestionToggle(questionText) {
        const questionElement = document.getElementById('research-question');
        const toggleButton = document.getElementById('question-toggle');
        
        if (!questionElement || !toggleButton) return;
        
        // Check if question is long enough to warrant truncation
        // Look for both actual newlines and escaped \n sequences
        const actualNewlines = (questionText.match(/\n/g) || []).length;
        const escapedNewlines = (questionText.match(/\\n/g) || []).length;
        const totalNewlines = actualNewlines + escapedNewlines;
        
        // Show toggle if: long text (>200 chars), many newlines (>3), or contains markdown headers
        const isLong = questionText.length > 200;
        const hasManyLines = totalNewlines > 3;
        const hasMarkdown = questionText.includes('#') || questionText.includes('##');
        
        console.log('Question length:', questionText.length, 'Newlines:', totalNewlines, 'Should show toggle:', isLong || hasManyLines || hasMarkdown);
        
        if (isLong || hasManyLines || hasMarkdown) {
            toggleButton.style.display = 'inline-block';
            
            // Remove old listener if exists
            const newToggle = toggleButton.cloneNode(true);
            toggleButton.parentNode.replaceChild(newToggle, toggleButton);
            
            // Add click handler
            newToggle.addEventListener('click', () => {
                const isExpanded = questionElement.classList.contains('expanded');
                
                if (isExpanded) {
                    questionElement.classList.remove('expanded');
                    newToggle.textContent = '▼ Show more';
                } else {
                    questionElement.classList.add('expanded');
                    newToggle.textContent = '▲ Show less';
                }
            });
        } else {
            toggleButton.style.display = 'none';
            questionElement.classList.remove('expanded');
        }
    }

    renderCompletionStatus(session) {
        const banner = document.getElementById('completion-banner');
        const title = document.getElementById('completion-title');
        const message = document.getElementById('completion-message');
        const reportLink = document.getElementById('completion-report-link');

        if (session.status === 'completed') {
            banner.classList.add('show');
            title.textContent = '✅ Research Complete!';

            const completedTime = session.completed_at ?
                new Date(session.completed_at).toLocaleString() :
                'recently';
            message.textContent = `Research session finished ${completedTime}`;

            // Get actual report filename from events
            const completionEvent = this.currentEvents?.find(e => 
                e.type === 'research_complete' || e.type === 'mission_completed');
            const reportFile = completionEvent?.data?.report_file || 'mission-report.md';

            // Update link href dynamically
            reportLink.href = reportFile;
            reportLink.style.display = 'inline-block';

            // Stop the runtime counter - research is done
            if (this.runtimeInterval) {
                clearInterval(this.runtimeInterval);
                this.runtimeInterval = null;
            }
        } else if (session.status === 'failed') {
            banner.classList.add('show', 'error');
            title.textContent = '❌ Research Failed';
            message.textContent = session.error || 'Research encountered an error and could not complete.';
            reportLink.style.display = 'none';

            // Stop the runtime counter on failure too
            if (this.runtimeInterval) {
                clearInterval(this.runtimeInterval);
                this.runtimeInterval = null;
            }
        } else {
            // In progress - don't show banner
            banner.classList.remove('show');
        }
    }

    startLiveRuntime(createdAt) {
        const startTime = new Date(createdAt);

        const updateRuntime = () => {
            const now = new Date();
            const elapsed = Math.floor((now - startTime) / 1000);

            const hours = Math.floor(elapsed / 3600);
            const mins = Math.floor(elapsed / 60);
            const secs = elapsed % 60;

            let runtimeText;
            if (hours > 0) {
                runtimeText = `${hours}h ${mins % 60}m`;
            } else if (mins > 0) {
                runtimeText = `${mins}m ${secs}s`;
            } else {
                runtimeText = `${secs}s`;
            }

            const runtimeEl = document.getElementById('stat-runtime');
            if (runtimeEl) {
                runtimeEl.textContent = runtimeText;
            }
        };

        // Update immediately
        updateRuntime();

        // Only create interval once (it's already checked in renderHeader)
        // This function is now only called once per session
        this.runtimeInterval = setInterval(updateRuntime, 1000);
    }

    renderStats(metrics) {
        if (!metrics) {
            // Show loading indicator if metrics don't exist yet
            this.showLoadingState();
            return;
        }
        
        // Remove loading indicator if it exists
        this.hideLoadingState();

        document.getElementById('stat-iteration').textContent = metrics.iteration || 0;
        document.getElementById('stat-confidence').textContent =
            Math.round((metrics.confidence || 0) * 100) + '%';
        document.getElementById('stat-entities').textContent =
            metrics.knowledge?.entities || 0;
        document.getElementById('stat-claims').textContent =
            metrics.knowledge?.claims || 0;
        document.getElementById('stat-cost').textContent =
            (metrics.costs?.total_usd || 0).toFixed(2);
        document.getElementById('stat-cost-per-iter').textContent =
            (metrics.costs?.per_iteration || 0).toFixed(2);

        // Runtime is now calculated dynamically in startLiveRuntime() for live updates
        // No need to set it here - it updates every second automatically
    }
    
    showLoadingState() {
        const statElements = [
            'stat-iteration',
            'stat-confidence', 
            'stat-entities',
            'stat-claims',
            'stat-cost',
            'stat-cost-per-iter'
        ];
        
        statElements.forEach(id => {
            const el = document.getElementById(id);
            if (el && el.textContent === '0' || el.textContent === '0%' || el.textContent === '0.00') {
                el.innerHTML = '<span style="opacity: 0.5; font-size: 0.8em;">...</span>';
            }
        });
    }
    
    hideLoadingState() {
        // Loading state is automatically hidden when real values are set
        // No action needed
    }

    renderTasks(tasks) {
        if (!tasks || !tasks.tasks) return;

        const container = document.getElementById('tasks-container');

        // Detect new tasks
        const currentTaskIds = new Set(tasks.tasks.map(t => t.id));
        const brandNewTasks = new Set();

        currentTaskIds.forEach(id => {
            if (!this.knownTaskIds.has(id)) {
                brandNewTasks.add(id);
            }
        });

        // Move previously new tasks to known
        this.newTaskIds.forEach(id => {
            if (!brandNewTasks.has(id)) {
                this.knownTaskIds.add(id);
            }
        });

        // Update tracking sets
        this.newTaskIds = brandNewTasks;
        currentTaskIds.forEach(id => this.knownTaskIds.add(id));

        // Group tasks by status
        const grouped = {
            in_progress: [],
            pending: [],
            completed: [],
            failed: []
        };

        tasks.tasks.forEach(task => {
            const status = task.status || 'pending';
            if (grouped[status]) {
                grouped[status].push(task);
            }
        });

        // Render tasks grouped by status
        let html = '';

        // Add status summary
        const summary = [];
        if (grouped.in_progress.length > 0) summary.push(`🔄 ${grouped.in_progress.length} active`);
        if (grouped.pending.length > 0) summary.push(`⏳ ${grouped.pending.length} pending`);
        if (grouped.completed.length > 0) summary.push(`✅ ${grouped.completed.length} done`);
        if (grouped.failed.length > 0) summary.push(`❌ ${grouped.failed.length} failed`);
        if (brandNewTasks.size > 0) summary.push(`🆕 ${brandNewTasks.size} new`);

        if (summary.length > 0) {
            html += `<div style="font-size: 0.75em; padding: 6px 12px; margin-bottom: 10px; opacity: 0.7; border-bottom: 1px solid rgba(255,255,255,0.1);">${summary.join(' • ')}</div>`;
        }

        // In progress
        if (grouped.in_progress.length > 0) {
            html += grouped.in_progress.map(task =>
                this.renderTaskItem(task, '🔄', brandNewTasks.has(task.id))
            ).join('');
        }

        // Pending
        if (grouped.pending.length > 0) {
            html += grouped.pending.map(task =>
                this.renderTaskItem(task, '⏳', brandNewTasks.has(task.id))
            ).join('');
        }

        // Completed (show last 5)
        if (grouped.completed.length > 0) {
            html += grouped.completed.slice(-5).map(task =>
                this.renderTaskItem(task, '✅', false)
            ).join('');
        }

        // Failed
        if (grouped.failed.length > 0) {
            html += grouped.failed.map(task =>
                this.renderTaskItem(task, '❌', brandNewTasks.has(task.id))
            ).join('');
        }

        container.innerHTML = html || '<div class="empty-state">No tasks</div>';
    }

    renderTaskItem(task, emoji, isNew) {
        const newBadge = isNew ? ' <span style="background: #4a90e2; padding: 2px 6px; border-radius: 3px; font-size: 0.7em; font-weight: bold; margin-left: 5px;">NEW</span>' : '';
        const agent = task.agent || 'unknown';
        const desc = task.query || task.description || task.type || 'No description';
        const truncDesc = desc.length > 60 ? desc.substring(0, 60) + '...' : desc;

        return `
            <div class="task-item" style="font-size: 0.85em; padding: 8px 12px; margin-bottom: 6px; background: rgba(255,255,255,0.05); border-radius: 4px; display: flex; align-items: center;" title="${this.escapeHtml(desc)}">
                <span style="margin-right: 8px; font-size: 1.2em;">${emoji}</span>
                <span style="flex: 1;"><strong style="color: #4a90e2;">${agent}</strong> - ${truncDesc}${newBadge}</span>
            </div>
        `;
    }

    renderObservations(observations) {
        // Store observations for modal
        this.currentObservations = observations || [];
        
        // Update inline health card
        const inlineContainer = document.getElementById('health-container-inline');
        if (inlineContainer) {
            if (!observations || observations.length === 0) {
                inlineContainer.innerHTML = '<div class="health-summary">✅ No issues detected</div>';
            } else {
                const criticalCount = observations.filter(o => o.data?.severity === 'critical').length;
                const warningCount = observations.filter(o => o.data?.severity === 'warning').length;
                const infoCount = observations.filter(o => o.data?.severity === 'info').length;
                
                const parts = [];
                if (criticalCount > 0) parts.push(`🔴 ${criticalCount} critical`);
                if (warningCount > 0) parts.push(`⚠️ ${warningCount} warning`);
                if (infoCount > 0) parts.push(`ℹ️ ${infoCount} info`);
                
                inlineContainer.innerHTML = `<div class="health-summary">${parts.join(' • ')}</div>`;
            }
        }

        if (!observations || observations.length === 0) {
            return;
        }

        // Group by severity for display order: critical, warning, info
        const criticalObs = observations.filter(o => o.data?.severity === 'critical');
        const warningObs = observations.filter(o => o.data?.severity === 'warning');
        const infoObs = observations.filter(o => o.data?.severity === 'info');
        const orderedObs = [...criticalObs, ...warningObs, ...infoObs];

        // Take top 10
        const displayObs = orderedObs.slice(0, 10);

        // Note: health-container was removed from sidebar, this is now unused
        const container = document.getElementById('health-container');
        if (!container) return;
        
        container.innerHTML = displayObs.map(obs => {
            const data = obs.data || {};
            const severity = data.severity || 'info';
            const component = data.component || 'unknown';
            const observation = data.observation || 'No description';
            const suggestion = data.suggestion || '';
            const timestamp = obs.timestamp || '';

            // Severity icons
            const icons = {
                critical: '🔴',
                warning: '⚠️',
                info: 'ℹ️'
            };
            const icon = icons[severity] || '•';

            // Format timestamp
            const timeStr = timestamp ? new Date(timestamp).toLocaleTimeString() : '';

            return `
                <div class="observation-item ${severity}">
                    <div class="observation-header">
                        <span class="observation-severity">${icon}</span>
                        <span class="observation-component">${this.escapeHtml(component)}</span>
                    </div>
                    <div class="observation-text">${this.escapeHtml(observation)}</div>
                    ${suggestion ? `<div class="observation-suggestion">💡 ${this.escapeHtml(suggestion)}</div>` : ''}
                    ${timeStr ? `<div class="observation-time">${timeStr}</div>` : ''}
                </div>
            `;
        }).join('');
    }

    renderToolCalls(events) {
        if (!events || events.length === 0) return;

        const container = document.getElementById('tools-container');

        // Filter for tool use events and group by tool_use_start
        const toolCalls = [];
        const toolStarts = events.filter(e => e.type === 'tool_use_start');
        const usedCompleteEvents = new Set(); // Track which complete events we've matched

        // For each tool start, find its corresponding complete event
        toolStarts.forEach(startEvent => {
            const tool = startEvent.data.tool;
            
            // Hide internal tools (Bash, TodoRead)
            if (tool === 'Bash' || tool === 'TodoRead') {
                return;
            }
            
            const agent = startEvent.data.agent || 'unknown';
            let summary = startEvent.data.input_summary || '';
            const timestamp = startEvent.timestamp;
            const startTime = new Date(timestamp).getTime();
            
            // For TodoWrite, add "Planning: " prefix if not already there
            if (tool === 'TodoWrite' && summary && !summary.startsWith('Planning:')) {
                summary = 'Planning: ' + summary;
            }

            // Find corresponding complete event
            // Match by: same tool, not yet used, within 60s, closest timestamp
            let bestMatch = null;
            let bestTimeDiff = Infinity;
            
            events.forEach((e, index) => {
                if (e.type === 'tool_use_complete' &&
                    e.data.tool === tool &&
                    !usedCompleteEvents.has(index)) {
                    
                    const completeTime = new Date(e.timestamp).getTime();
                    const timeDiff = completeTime - startTime;
                    
                    // Complete event should be after start, within 60s, and closest
                    if (timeDiff >= 0 && timeDiff < 60000 && timeDiff < bestTimeDiff) {
                        bestMatch = { event: e, index };
                        bestTimeDiff = timeDiff;
                    }
                }
            });

            // Mark the matched complete event as used
            if (bestMatch) {
                usedCompleteEvents.add(bestMatch.index);
            }

            const duration = bestMatch ? bestMatch.event.data.duration_ms : null;
            const status = bestMatch ? bestMatch.event.data.status : 'pending';

            toolCalls.push({
                timestamp,
                tool,
                agent,
                summary,
                duration,
                status
            });
        });

        // Show last 20 tool calls, most recent first
        const recentCalls = toolCalls.slice(-20).reverse();

        if (recentCalls.length === 0) {
            container.innerHTML = '<div class="empty-state">No tool calls yet</div>';
            return;
        }

        container.innerHTML = recentCalls.map(call => {
            const time = new Date(call.timestamp).toLocaleTimeString('en-US', {
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });

            const statusClass = call.status === 'success' ? 'success' :
                (call.status === 'failed' ? 'failed' : 'pending');
            const statusIconClass = call.status === 'success' ? 'tool-status-success' :
                (call.status === 'failed' ? 'tool-status-failed' : 'tool-status-pending');
            const statusIcon = call.status === 'success' ? '✓' :
                (call.status === 'failed' ? '✗' : '⏳');

            let durationText = '';
            if (call.duration !== null) {
                if (call.duration > 1000) {
                    durationText = `${(call.duration / 1000).toFixed(1)}s`;
                } else {
                    durationText = `${call.duration}ms`;
                }
            }

            // Truncate summary intelligently

            // For file paths, show the end (filename) instead of beginning
            let truncSummary;
            if (call.summary.length > 35) {
                if (call.tool === 'Read' || call.tool === 'Write' || call.tool === 'Edit' || call.tool === 'MultiEdit' || call.tool === 'Glob') {
                    // File path: show "...filename" instead of "long/path/to..."
                    truncSummary = '...' + call.summary.substring(call.summary.length - 32);
                } else {
                    // Other tools: truncate from start
                    truncSummary = call.summary.substring(0, 35) + '...';
                }
            } else {
                truncSummary = call.summary;
            }
            
            // Get friendly tool name
            const friendlyToolName = this.getFriendlyToolName(call.tool);

            return `
                <div class="tool-item ${statusClass}" title="${this.escapeHtml(call.summary)}">
                    <span class="tool-icon">${this.getToolIcon(call.tool)}</span>
                    <div class="tool-content">
                        <div class="tool-header">
                            <span class="tool-name">${friendlyToolName}</span>
                            <span class="tool-status ${statusIconClass}">${statusIcon}</span>
                        </div>
                        <div class="tool-details">${this.escapeHtml(truncSummary)}</div>
                        <div class="tool-footer">
                            <span>${call.agent}</span>
                            <span>${durationText || time}</span>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    }
    
    getFriendlyToolName(toolName) {
        const friendlyNames = {
            'WebSearch': 'Web Search',
            'WebFetch': 'Fetch Page',
            'TodoWrite': 'Planning',
            'TodoRead': 'Check Tasks',
            'MultiEdit': 'Edit Files',
            'Grep': 'Search',
            'Glob': 'Find Files'
        };
        return friendlyNames[toolName] || toolName;
    }

    // ========================================
    // JOURNAL VIEW METHODS
    // ========================================

    renderJournal(events) {
        // Store events for toggle methods
        this.lastEvents = events;
        
        const container = document.getElementById('journal-container');
        const lastUpdated = document.getElementById('last-updated-journal');
        
        if (!events || events.length === 0) {
            container.innerHTML = '<div class="empty-state">No activity yet</div>';
            return;
        }

        const entries = this.groupEventsIntoJournalEntries(events);
        
        if (entries.length === 0) {
            container.innerHTML = '<div class="empty-state">Starting research...</div>';
            return;
        }

        const html = entries.map(entry => this.formatJournalEntry(entry)).join('');
        container.innerHTML = html;
        
        // Update last updated time
        if (lastUpdated) {
            const now = new Date().toLocaleTimeString();
            lastUpdated.textContent = `Last updated: ${now}`;
        }
    }

    groupEventsIntoJournalEntries(events) {
        const entries = [];
        
        // Entry 1: Session/Mission start
        const sessionCreated = events.find(e => e.type === 'session_created' || e.type === 'mission_started');
        if (sessionCreated) {
            const objective = sessionCreated.data?.objective || 'research query';
            entries.push({
                type: 'milestone',
                icon: '🎯',
                title: 'Research Session Started',
                startTime: sessionCreated.timestamp,
                endTime: null,
                content: `I initialized a new research session and prepared to analyze your query: "${objective}"`,
                agent: 'system',
                metadata: {},
                events: [sessionCreated]
            });
        }
        
        // Entry 2-N: Agent invocations
        const agentNames = ['mission-orchestrator', 'research-planner', 'academic-researcher', 'web-researcher', 'synthesis-agent'];
        
        agentNames.forEach(agentName => {
            const invocations = events.filter(e => e.type === 'agent_invocation' && e.data.agent === agentName);
            const results = events.filter(e => e.type === 'agent_result' && e.data.agent === agentName);
            
            // Match invocations with results
            for (let i = 0; i < Math.min(invocations.length, results.length); i++) {
                const invocation = invocations[i];
                const result = results[i];
                
                entries.push({
                    type: this.getEntryType(agentName),
                    icon: this.getAgentIcon(agentName),
                    title: this.getAgentTitle(agentName),
                    startTime: invocation.timestamp,
                    endTime: result.timestamp,
                    content: this.formatAgentWork(agentName, result.data),
                    agent: agentName,
                    metadata: {
                        duration: this.calculateDurationSeconds(invocation.timestamp, result.timestamp),
                        cost: result.data.cost_usd || 0,
                        ...result.data // Include all agent-specific metadata
                    },
                    events: [invocation, result],
                    tasks: this.getTasksForAgent(agentName, events),
                    tools: this.getToolsForAgent(agentName, events, invocation.timestamp, result.timestamp)
                });
            }
        });
        
        // Entry N+1: Iteration completions
        events.filter(e => e.type === 'iteration_complete').forEach(e => {
            entries.push({
                type: 'milestone',
                icon: '✅',
                title: `Iteration ${e.data.iteration} Complete`,
                startTime: e.timestamp,
                endTime: null,
                content: this.formatIterationComplete(e.data),
                agent: 'mission-orchestrator',
                metadata: e.data.stats || {},
                events: [e]
            });
        });
        
        // Entry N+2: Research completion (support both old and new event types)
        const researchComplete = events.find(e => e.type === 'research_complete' || e.type === 'mission_completed');
        if (researchComplete) {
            const reportFile = researchComplete.data?.report_file || 'mission-report.md';
            
            // For mission_completed events, we need to enrich data from metrics
            // The formatResearchComplete function expects claims_synthesized, entities_integrated, report_sections
            const completionData = researchComplete.type === 'mission_completed' ? {
                claims_synthesized: this.currentMetrics?.knowledge?.claims || 0,
                entities_integrated: this.currentMetrics?.knowledge?.entities || 0,
                report_sections: 0, // Not tracked separately
                report_file: reportFile
            } : researchComplete.data;
            
            entries.push({
                type: 'milestone',
                icon: '🎉',
                title: 'Research Report Complete',
                startTime: researchComplete.timestamp,
                endTime: null,
                content: this.formatResearchComplete(completionData),
                agent: 'synthesis-agent',
                metadata: {
                    claims_synthesized: completionData.claims_synthesized || 0,
                    entities_integrated: completionData.entities_integrated || 0,
                    report_sections: completionData.report_sections || 0,
                    report_file: reportFile
                },
                events: [researchComplete]
            });
        }
        
        // Add "in progress" entries for unfinished work
        // These will appear at the top (newest first) to show current activity
        agentNames.forEach(agentName => {
            const invocations = events.filter(e => e.type === 'agent_invocation' && e.data.agent === agentName);
            const results = events.filter(e => e.type === 'agent_result' && e.data.agent === agentName);
            
            // If more invocations than results, last invocation is in progress
            if (invocations.length > results.length) {
                const inProgressInvocation = invocations[invocations.length - 1];
                const elapsedSeconds = this.calculateDurationSeconds(inProgressInvocation.timestamp, new Date().toISOString());
                
                entries.push({
                    type: 'in_progress',
                    icon: '⏳',
                    title: `${this.getAgentTitle(agentName)} (In Progress)`,
                    startTime: inProgressInvocation.timestamp,
                    endTime: null,
                    content: `Currently working... (${Math.floor(elapsedSeconds)}s elapsed)`,
                    agent: agentName,
                    metadata: {
                        elapsed: elapsedSeconds,
                        status: 'running'
                    },
                    events: [inProgressInvocation],
                    tasks: this.getTasksForAgent(agentName, events), // Show tasks assigned to this agent
                    tools: [] // No completed tools yet
                });
            }
        });
        
        // Also check for in-progress tasks
        const taskStarts = events.filter(e => e.type === 'task_started');
        const taskEnds = events.filter(e => e.type === 'task_completed' || e.type === 'task_failed');
        const taskEndIds = new Set(taskEnds.map(e => e.data.task_id));
        
        taskStarts.forEach(taskStart => {
            if (!taskEndIds.has(taskStart.data.task_id)) {
                const elapsedSeconds = this.calculateDurationSeconds(taskStart.timestamp, new Date().toISOString());
                entries.push({
                    type: 'in_progress',
                    icon: '📋',
                    title: `Task ${taskStart.data.task_id} (In Progress)`,
                    startTime: taskStart.timestamp,
                    endTime: null,
                    content: `Working on: "${taskStart.data.query}" (${Math.floor(elapsedSeconds)}s elapsed)`,
                    agent: taskStart.data.agent,
                    metadata: {
                        elapsed: elapsedSeconds,
                        status: 'running',
                        task_id: taskStart.data.task_id
                    },
                    events: [taskStart],
                    tasks: [],
                    tools: []
                });
            }
        });
        
        // Sort by time (newest first)
        return entries.sort((a, b) => new Date(b.startTime) - new Date(a.startTime));
    }

    getEntryType(agentName) {
        const types = {
            'research-planner': 'analysis',
            'academic-researcher': 'research',
            'web-researcher': 'research',
            'synthesis-agent': 'finding',
            'research-coordinator': 'analysis'
        };
        return types[agentName] || 'research';
    }

    getAgentIcon(agentName) {
        const icons = {
            'research-planner': '🗂️',
            'academic-researcher': '🔍',
            'web-researcher': '🌐',
            'synthesis-agent': '✨',
            'research-coordinator': '🧭'
        };
        return icons[agentName] || '🤖';
    }

    getAgentTitle(agentName) {
        const titles = {
            'mission-orchestrator': 'Coordinating Research Step',
            'research-planner': 'Research Strategy Planned',
            'academic-researcher': 'Searching Academic Literature',
            'web-researcher': 'Searching Web Sources',
            'synthesis-agent': 'Synthesizing Findings',
            'research-coordinator': 'Coordinating Research'
        };
        return titles[agentName] || 'Working';
    }

    formatAgentWork(agentName, resultData) {
        const templates = {
            'research-planner': () => {
                const tasks = resultData.tasks_generated || 0;
                return `I analyzed the query and identified ${tasks} critical research area${tasks !== 1 ? 's' : ''} to explore.`;
            },
            'academic-researcher': () => {
                const papers = resultData.papers_found || 0;
                const searches = resultData.searches_performed || 0;
                return `I conducted ${searches} systematic search${searches !== 1 ? 'es' : ''} across academic databases and found ${papers} relevant paper${papers !== 1 ? 's' : ''} with focus on peer-reviewed sources.`;
            },
            'web-researcher': () => {
                const sources = resultData.sources_found || 0;
                const searches = resultData.searches_performed || 0;
                return `I performed ${searches} web search${searches !== 1 ? 'es' : ''} and analyzed ${sources} source${sources !== 1 ? 's' : ''} to gather current information on the research topic.`;
            },
            'synthesis-agent': () => {
                const claims = resultData.claims_synthesized || 0;
                const gaps = resultData.gaps_found || 0;
                return `I synthesized ${claims} claim${claims !== 1 ? 's' : ''} from all gathered sources and identified ${gaps} knowledge gap${gaps !== 1 ? 's' : ''} requiring further investigation.`;
            },
            'research-coordinator': () => {
                const entities = resultData.entities_discovered || 0;
                const claims = resultData.claims_validated || 0;
                const gaps = resultData.gaps_identified || 0;
                return `I processed the research findings and discovered ${entities} key entit${entities !== 1 ? 'ies' : 'y'}, validated ${claims} claim${claims !== 1 ? 's' : ''}, and identified ${gaps} gap${gaps !== 1 ? 's' : ''} in the current knowledge.`;
            }
        };
        
        const formatter = templates[agentName];
        return formatter ? formatter() : `I completed ${agentName} work.`;
    }

    formatIterationComplete(data) {
        const iteration = data.iteration || '?';
        const stats = data.stats || {};
        const claims = stats.total_claims || 0;
        const entities = stats.total_entities || 0;
        
        return `I completed iteration ${iteration} and analyzed all pending tasks. Knowledge graph now contains ${entities} entit${entities !== 1 ? 'ies' : 'y'} and ${claims} validated claim${claims !== 1 ? 's' : ''}.`;
    }

    formatResearchComplete(data) {
        const claims = data.claims_synthesized || 0;
        const entities = data.entities_integrated || 0;
        const sections = data.report_sections || 0;
        const reportFile = data.report_file || 'mission-report.md';
        
        // Build message based on whether we have section count
        const sectionText = sections > 0 
            ? `with ${sections} section${sections !== 1 ? 's' : ''}, ` 
            : '';
        
        return `I synthesized all research findings into a comprehensive report ${sectionText}integrating ${claims} claim${claims !== 1 ? 's' : ''} and ${entities} entit${entities !== 1 ? 'ies' : 'y'}. 
        
📄 <strong><a href="${reportFile}" target="_blank">View Research Report</a></strong>

📖 <strong><a href="research-journal.md" target="_blank">View Research Journal</a></strong> (Sequential timeline with full details)`;
    }

    getTasksForAgent(agentName, events) {
        const tasks = {};
        
        // For research-planner, show ALL tasks it generated (first iteration tasks)
        if (agentName === 'research-planner') {
            events.forEach(e => {
                if (e.type === 'task_started' || e.type === 'task_completed' || e.type === 'task_failed') {
                    const taskId = e.data.task_id;
                    if (!tasks[taskId]) {
                        tasks[taskId] = {
                            id: taskId,
                            query: e.data.query || '',
                            status: 'pending',
                            agent: e.data.agent  // Show which agent will execute it
                        };
                    }
                    
                    if (e.type === 'task_started') {
                        tasks[taskId].status = 'in-progress';
                        tasks[taskId].startTime = e.timestamp;
                    } else if (e.type === 'task_completed') {
                        tasks[taskId].status = 'completed';
                        tasks[taskId].endTime = e.timestamp;
                    } else if (e.type === 'task_failed') {
                        tasks[taskId].status = e.data.recoverable === 'true' || e.data.recoverable === true ? 
                            'failed-recoverable' : 'failed-critical';
                        tasks[taskId].error = e.data.error;
                    }
                }
            });
        } else {
            // For other agents, show only tasks they executed
            events.forEach(e => {
                if ((e.type === 'task_started' || e.type === 'task_completed' || e.type === 'task_failed') 
                    && e.data.agent === agentName) {
                    
                    const taskId = e.data.task_id;
                    if (!tasks[taskId]) {
                        tasks[taskId] = {
                            id: taskId,
                            query: e.data.query || '',
                            status: 'pending',
                            agent: agentName
                        };
                    }
                    
                    if (e.type === 'task_started') {
                        tasks[taskId].status = 'in-progress';
                        tasks[taskId].startTime = e.timestamp;
                    } else if (e.type === 'task_completed') {
                        tasks[taskId].status = 'completed';
                        tasks[taskId].endTime = e.timestamp;
                    } else if (e.type === 'task_failed') {
                        tasks[taskId].status = e.data.recoverable === 'true' || e.data.recoverable === true ? 
                            'failed-recoverable' : 'failed-critical';
                        tasks[taskId].error = e.data.error;
                    }
                }
            });
        }
        
        return Object.values(tasks);
    }

    getToolsForAgent(agentName, events, startTime, endTime) {
        const tools = [];
        const startMs = new Date(startTime).getTime();
        const endMs = new Date(endTime).getTime();
        
        // Find tool_use_start events for this agent in the time range
        const toolStarts = events.filter(e => 
            e.type === 'tool_use_start' &&
            e.data.agent === agentName &&
            new Date(e.timestamp).getTime() >= startMs &&
            new Date(e.timestamp).getTime() <= endMs
        );
        
        toolStarts.forEach(start => {
            const tool = start.data.tool;
            const startToolTime = new Date(start.timestamp).getTime();
            
            // Find corresponding complete event
            const complete = events.find(e => 
                e.type === 'tool_use_complete' &&
                e.data.tool === tool &&
                new Date(e.timestamp).getTime() > startToolTime &&
                new Date(e.timestamp).getTime() <= endMs &&
                new Date(e.timestamp).getTime() - startToolTime < 60000
            );
            
            tools.push({
                tool: tool,
                icon: this.getToolIcon(tool),
                details: start.data.input_summary || '',
                status: complete ? (complete.data.status || 'success') : 'pending',
                duration: complete ? complete.data.duration_ms : null,
                result: complete ? this.formatToolResult(tool, complete.data) : null
            });
        });
        
        return tools;
    }

    getToolIcon(toolName) {
        const icons = {
            'WebSearch': '🔍',
            'WebFetch': '🌐',
            'Read': '📄',
            'Write': '✏️',
            'Grep': '🔎',
            'Glob': '📁',
            'Bash': '🔧',
            'Task': '📋',
            'TodoWrite': '📋',
            'TodoRead': '📋'
        };
        return icons[toolName] || '🔧';
    }

    formatToolResult(tool, data) {
        if (data.status === 'failed' || data.status === 'error') {
            return 'failed';
        }
        
        const duration = data.duration_ms;
        if (duration) {
            return `${(duration / 1000).toFixed(1)}s`;
        }
        
        return 'success';
    }

    formatJournalEntry(entry) {
        const timeRange = entry.endTime ? 
            `${this.formatTime(entry.startTime)} - ${this.formatTime(entry.endTime)}` :
            this.formatTime(entry.startTime);
        
        // Generate unique ID for this entry (for tracking expansion state)
        const entryId = `${entry.startTime}_${entry.agent}`;
        
        return `
            <div class="journal-entry ${entry.type}" data-entry-id="${entryId}">
                <span class="journal-time">${timeRange}</span>
                
                <div class="journal-title">
                    <span class="icon">${entry.icon}</span>
                    <span>${entry.title}</span>
                </div>
                
                <div class="journal-content">
                    ${entry.content}
                </div>
                
                ${this.renderReasoningSection(entry, entryId)}
                
                <div class="journal-metadata">
                    <span>🤖 ${entry.agent}</span>
                    ${this.formatMetadata(entry.metadata, entry)}
                </div>
                
                ${entry.tasks && entry.tasks.length > 0 ? this.renderTasksExpander(entry, entryId) : ''}
                ${entry.tools && entry.tools.length > 0 ? this.renderToolsExpander(entry, entryId) : ''}
            </div>
        `;
    }

    formatMetadata(metadata, entry) {
        const parts = [];
        
        if (metadata.duration !== undefined) {
            const minutes = Math.floor(metadata.duration / 60);
            const seconds = metadata.duration % 60;
            const timeStr = minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;
            parts.push(`<span>⏱️ ${timeStr}</span>`);
        }
        
        if (metadata.cost !== undefined) {
            parts.push(`<span>💰 $${metadata.cost.toFixed(3)}</span>`);
        }
        
        if (metadata.tasks_generated) {
            parts.push(`<span>${metadata.tasks_generated} tasks generated</span>`);
        }
        
        if (metadata.papers_found) {
            parts.push(`<span>📄 ${metadata.papers_found} papers found</span>`);
        }
        
        if (metadata.sources_found) {
            parts.push(`<span>🌐 ${metadata.sources_found} sources found</span>`);
        }
        
        if (metadata.searches_performed) {
            parts.push(`<span>🔍 ${metadata.searches_performed} searches</span>`);
        }
        
        if (metadata.entities_discovered) {
            parts.push(`<span>📊 ${metadata.entities_discovered} entities</span>`);
        }
        
        if (metadata.claims_validated) {
            parts.push(`<span>💡 ${metadata.claims_validated} claims</span>`);
        }
        
        if (metadata.gaps_identified) {
            parts.push(`<span>⚠️ ${metadata.gaps_identified} gaps</span>`);
        }
        
        if (metadata.contradictions_detected) {
            parts.push(`<span>🔴 ${metadata.contradictions_detected} contradictions</span>`);
        }
        
        // Add task progress inline in metadata if there are tasks
        if (entry && entry.tasks && entry.tasks.length > 0) {
            const completed = entry.tasks.filter(t => t.status === 'completed').length;
            const inProgress = entry.tasks.filter(t => t.status === 'in-progress').length;
            const pending = entry.tasks.filter(t => t.status === 'pending').length;
            
            let progressHtml = `<span class="task-progress">
                <span class="task-progress-item">
                    <span class="count">${entry.tasks.length}</span> generated
                </span>`;
            
            if (completed > 0) {
                progressHtml += `<span style="opacity: 0.3;">•</span>
                <span class="task-progress-item" style="color: #10b981;">
                    <span class="count">${completed}</span> completed
                </span>`;
            }
            
            if (inProgress > 0) {
                progressHtml += `<span style="opacity: 0.3;">•</span>
                <span class="task-progress-item" style="color: #3b82f6;">
                    <span class="count">${inProgress}</span> in progress
                </span>`;
            }
            
            if (pending > 0) {
                progressHtml += `<span style="opacity: 0.3;">•</span>
                <span class="task-progress-item" style="color: #fbbf24;">
                    <span class="count">${pending}</span> pending
                </span>`;
            }
            
            progressHtml += `</span>`;
            parts.push(progressHtml);
        }
        
        return parts.join('\n                    ');
    }

    renderReasoningSection(entry, entryId) {
        // Extract reasoning from metadata (orchestrator adds it after flattening)
        const reasoning = entry.metadata?.reasoning;
        if (!reasoning) return '';
        
        // Build reasoning content
        let reasoningHtml = '<div style="margin: 12px 0; padding: 12px; background: rgba(99, 102, 241, 0.1); border-left: 3px solid #6366f1; border-radius: 4px;">';
        reasoningHtml += '<div style="font-weight: 600; color: #6366f1; margin-bottom: 8px;">💡 Research Reasoning</div>';
        
        if (reasoning.synthesis_approach) {
            reasoningHtml += `<div style="margin-bottom: 6px;"><strong>Approach:</strong> ${this.escapeHtml(reasoning.synthesis_approach)}</div>`;
        }
        
        if (reasoning.gap_prioritization) {
            reasoningHtml += `<div style="margin-bottom: 6px;"><strong>Priority:</strong> ${this.escapeHtml(reasoning.gap_prioritization)}</div>`;
        }
        
        if (reasoning.key_insights && reasoning.key_insights.length > 0) {
            reasoningHtml += '<div style="margin-bottom: 6px;"><strong>Key Insights:</strong></div>';
            reasoningHtml += '<ul style="margin: 4px 0 0 20px; padding: 0;">';
            reasoning.key_insights.forEach(insight => {
                reasoningHtml += `<li style="margin-bottom: 2px;">${this.escapeHtml(insight)}</li>`;
            });
            reasoningHtml += '</ul>';
        }
        
        if (reasoning.strategic_decisions && reasoning.strategic_decisions.length > 0) {
            reasoningHtml += '<div style="margin-top: 6px;"><strong>Strategic Decisions:</strong></div>';
            reasoningHtml += '<ul style="margin: 4px 0 0 20px; padding: 0;">';
            reasoning.strategic_decisions.forEach(decision => {
                reasoningHtml += `<li style="margin-bottom: 2px;">${this.escapeHtml(decision)}</li>`;
            });
            reasoningHtml += '</ul>';
        }
        
        reasoningHtml += '</div>';
        return reasoningHtml;
    }

    renderTasksExpander(entry, entryId) {
        if (!entry.tasks || entry.tasks.length === 0) return '';
        
        const taskList = entry.tasks.map(task => `
            <li>
                <span>${this.escapeHtml(task.query || task.id)}</span>
                <span class="task-status-badge ${task.status}">${this.formatTaskStatus(task.status)}</span>
            </li>
        `).join('');
        
        const isExpanded = this.expandedJournalTasks.has(entryId);
        const expandedClass = isExpanded ? 'expanded' : '';
        const expandText = isExpanded ? 'View task breakdown ▲' : 'View task breakdown ▼';
        
        return `
            <span class="journal-expand" onclick="dashboard.toggleJournalTasks('${entryId}')">
                ${expandText}
            </span>
            <div class="journal-details ${expandedClass}">
                <ul style="list-style: none; padding: 0;">
                    ${taskList}
                </ul>
            </div>
        `;
    }

    formatTaskStatus(status) {
        const statusMap = {
            'pending': 'pending',
            'in-progress': 'doing',
            'completed': 'done',
            'failed-critical': 'failed',
            'failed-recoverable': 'retry'
        };
        return statusMap[status] || status;
    }

    renderToolsExpander(entry, entryId) {
        if (!entry.tools || entry.tools.length === 0) return '';
        
        const toolsList = entry.tools.map(tool => {
            // Smart truncation: show end of file paths, start of everything else
            let truncDetails;
            if (tool.details.length > 60) {
                if (tool.tool === 'Read' || tool.tool === 'Write' || tool.tool === 'Edit' || tool.tool === 'MultiEdit' || tool.tool === 'Glob') {
                    // File path: show "...filename"
                    truncDetails = '...' + tool.details.substring(tool.details.length - 57);
                } else {
                    // Other: show "start..."
                    truncDetails = tool.details.substring(0, 60) + '...';
                }
            } else {
                truncDetails = tool.details;
            }
            
            return `
                <div class="tool-used-item ${tool.status}">
                    <span class="tool-used-icon">${tool.icon}</span>
                    <span class="tool-used-name">${tool.tool}</span>
                    <span class="tool-used-details" title="${this.escapeHtml(tool.details)}">${this.escapeHtml(truncDetails)}</span>
                    <span class="tool-used-result ${tool.status}">
                        ${tool.result || '...'}
                    </span>
                </div>
            `;
        }).join('');
        
        const isExpanded = this.expandedJournalTools.has(entryId);
        const expandedClass = isExpanded ? 'expanded' : '';
        const expandText = isExpanded ? 'View tools used ▲' : 'View tools used ▼';
        
        return `
            <span class="journal-expand" onclick="dashboard.toggleJournalTools('${entryId}')" style="margin-top: 8px;">
                ${expandText}
            </span>
            <div class="tools-used ${expandedClass}">
                <div class="tools-used-title">Tools used by ${entry.agent}</div>
                ${toolsList}
            </div>
        `;
    }

    formatTime(timestamp) {
        return new Date(timestamp).toLocaleTimeString('en-US', { 
            hour: '2-digit', 
            minute: '2-digit',
            second: '2-digit',
            hour12: false 
        });
    }

    calculateDurationSeconds(startTime, endTime) {
        const start = new Date(startTime).getTime();
        const end = new Date(endTime).getTime();
        return Math.round((end - start) / 1000);
    }

    // ========================================
    // END JOURNAL VIEW METHODS
    // ========================================

    renderEvents(events) {
        if (!events || events.length === 0) return;

        // Filter out tool_use events - they're shown in the sidebar
        const meaningfulEvents = events.filter(e =>
            e.type !== 'tool_use_start' &&
            e.type !== 'tool_use_complete'
        );

        const container = document.getElementById('events-container');
        if (meaningfulEvents.length === 0) {
            // Check if research has started (session exists)
            const hasSession = events && events.length > 0;
            const message = hasSession ?
                'Starting research...' :
                'No activity yet';
            container.innerHTML = `<div class="empty-state">${message}</div>`;
            return;
        }

        container.innerHTML = meaningfulEvents.reverse().map((event, index) => {
            const time = new Date(event.timestamp).toLocaleTimeString();
            const message = this.formatEvent(event);
            const eventJson = JSON.stringify(event, null, 2);
            // Use timestamp + type as unique ID for each event
            const eventId = `${event.timestamp}_${event.type}`;
            const isExpanded = this.expandedEvents.has(eventId);
            const expandedClass = isExpanded ? 'event-expanded' : '';
            return `
                <div class="event-item ${expandedClass}" onclick="dashboard.toggleEvent('${eventId}')">
                    <span class="event-time">${time}</span> ${message}
                    <span class="event-expand">▼</span>
                    <div class="event-details"><pre>${this.escapeHtml(eventJson)}</pre></div>
                </div>
            `;
        }).join('');

        // Update last updated time
        const lastUpdated = document.getElementById('last-updated');
        if (lastUpdated) {
            const now = new Date().toLocaleTimeString();
            lastUpdated.textContent = `Last updated: ${now}`;
        }
    }

    toggleEvent(eventId) {
        if (this.expandedEvents.has(eventId)) {
            this.expandedEvents.delete(eventId);
        } else {
            this.expandedEvents.add(eventId);
        }
        // Find and toggle the element
        const items = document.querySelectorAll('.event-item');
        items.forEach(item => {
            if (item.getAttribute('onclick').includes(eventId)) {
                item.classList.toggle('event-expanded');
            }
        });
    }

    toggleJournalTasks(entryId) {
        if (this.expandedJournalTasks.has(entryId)) {
            this.expandedJournalTasks.delete(entryId);
        } else {
            this.expandedJournalTasks.add(entryId);
        }
        // Re-render journal to update UI
        const events = this.lastEvents || [];
        this.renderJournal(events);
    }

    toggleJournalTools(entryId) {
        if (this.expandedJournalTools.has(entryId)) {
            this.expandedJournalTools.delete(entryId);
        } else {
            this.expandedJournalTools.add(entryId);
        }
        // Re-render journal to update UI
        const events = this.lastEvents || [];
        this.renderJournal(events);
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    formatEvent(event) {
        switch (event.type) {
            case 'iteration_start':
                return `🔄 Started iteration ${event.data.iteration}`;
            case 'iteration_complete':
                return `✅ Completed iteration ${event.data.iteration}`;
            case 'task_started':
                return `▶️ ${event.data.agent} started task`;
            case 'task_completed':
                const cost = event.data.cost_usd > 0
                    ? ` ($${event.data.cost_usd.toFixed(3)})`
                    : '';
                return `✓ ${event.data.agent} completed${cost}`;
            case 'entity_added':
                return `📌 Added: ${event.data.name}`;
            case 'claim_added':
                return `💡 Claim (${Math.round((event.data.confidence || 0) * 100)}% confidence)`;
            case 'gap_detected':
                return `⚠️ Gap (${event.data.priority})`;
            case 'gap_resolved':
                return `✓ Gap resolved`;
            case 'mission_started':
                const objective = event.data.objective || 'Research mission';
                return `🚀 Starting research: ${objective}`;
            case 'mission_completed':
                const reportFile = event.data.report_file || 'mission-report.md';
                return `✅ Research complete! Report: ${reportFile}`;
            case 'agent_invocation':
                return `⚡ Invoking ${event.data.agent}`;
            case 'agent_result':
                const agentCost = event.data.cost_usd > 0
                    ? ` $${event.data.cost_usd.toFixed(3)}`
                    : '';
                const duration = event.data.duration_ms
                    ? ` ${(event.data.duration_ms / 1000).toFixed(1)}s`
                    : '';
                return `✓ ${event.data.agent}${duration}${agentCost}`;
            case 'system_observation':
                const severityIcon = {
                    critical: '🔴',
                    warning: '⚠️',
                    info: 'ℹ️'
                }[event.data?.severity] || '•';
                const component = event.data?.component || 'system';
                const observation = event.data?.observation || 'System observation';
                // Truncate long observations for display
                const truncObs = observation.length > 80 ?
                    observation.substring(0, 80) + '...' :
                    observation;
                return `${severityIcon} [${component}] ${truncObs}`;
            case 'observation_resolved':
                const resolvedComponent = event.data?.original_observation?.component || 'system';
                const resolution = event.data?.resolution || 'Issue resolved';
                const truncRes = resolution.length > 80 ?
                    resolution.substring(0, 80) + '...' :
                    resolution;
                return `✓ [${resolvedComponent}] ${truncRes}`;
            default:
                return `• ${event.type}`;
        }
    }
    
    async showEntities() {
        // Fetch knowledge graph
        const kg = await this.fetchJSON('knowledge-graph.json');
        if (!kg || !kg.entities) {
            alert('No entities data available');
            return;
        }
        
        const entities = kg.entities || [];
        if (entities.length === 0) {
            alert('No entities discovered yet');
            return;
        }
        
        // Show modal
        document.getElementById('modal-title').textContent = `Entities (${entities.length})`;
        const modalList = document.getElementById('modal-list');
        
        modalList.innerHTML = entities.map(entity => `
            <li class="modal-list-item">
                <div class="modal-list-item-title">${this.escapeHtml(entity.name || entity.id)}</div>
                <div class="modal-list-item-description">${this.escapeHtml(entity.description || 'No description')}</div>
            </li>
        `).join('');
        
        document.getElementById('modal-overlay').classList.add('active');
    }
    
    async showClaims() {
        // Fetch knowledge graph
        const kg = await this.fetchJSON('knowledge-graph.json');
        if (!kg || !kg.claims) {
            alert('No claims data available');
            return;
        }
        
        const claims = kg.claims || [];
        if (claims.length === 0) {
            alert('No claims validated yet');
            return;
        }
        
        // Show modal
        document.getElementById('modal-title').textContent = `Claims (${claims.length})`;
        const modalList = document.getElementById('modal-list');
        
        modalList.innerHTML = claims.map(claim => {
            const confidence = claim.confidence_score !== undefined 
                ? ` (${Math.round(claim.confidence_score * 100)}% confidence)` 
                : '';
            return `
                <li class="modal-list-item">
                    <div class="modal-list-item-title">${this.escapeHtml(claim.claim || claim.statement)}${confidence}</div>
                    <div class="modal-list-item-description">
                        ${claim.sources ? `📚 Sources: ${claim.sources.length}` : ''}
                    </div>
                </li>
            `;
        }).join('');
        
        document.getElementById('modal-overlay').classList.add('active');
    }
    
    closeModal(event) {
        // Only close if clicking overlay (not modal content)
        if (!event || event.target.id === 'modal-overlay' || event.target.classList.contains('modal-close')) {
            document.getElementById('modal-overlay').classList.remove('active');
        }
    }
}

const dashboard = new Dashboard();
document.addEventListener('DOMContentLoaded', () => {
    dashboard.init();
});

// Global functions for toggling journal entry details
function toggleDetails(element) {
    const details = element.nextElementSibling;
    if (details && details.classList.contains('journal-details')) {
        details.classList.toggle('expanded');
        element.textContent = details.classList.contains('expanded') ? 
            'View task breakdown ▲' : 'View task breakdown ▼';
    }
}

function toggleTools(element) {
    const tools = element.nextElementSibling;
    if (tools && tools.classList.contains('tools-used')) {
        tools.classList.toggle('expanded');
        element.textContent = tools.classList.contains('expanded') ? 
            'View tools used ▲' : 'View tools used ▼';
    }
}


// Force refresh when tab becomes visible (helps with file:// protocol caching)
document.addEventListener('visibilitychange', () => {
    if (!document.hidden && dashboard) {
        console.log('[Dashboard] Tab became visible - forcing refresh');
        dashboard.loadAndRender();
    }
});

// Manual refresh function
function manualRefresh() {
    console.log('[Dashboard] Manual refresh triggered');
    if (dashboard) {
        dashboard.loadAndRender();
    }
}
