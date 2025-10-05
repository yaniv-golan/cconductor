// Dashboard JavaScript - Real-time metrics
class Dashboard {
    constructor() {
        this.updateInterval = 3000; // 3 seconds
        this.expandedEvents = new Set(); // Track expanded event indices
        this.knownTaskIds = new Set(); // Track tasks we've seen before
        this.newTaskIds = new Set(); // Track newly added tasks
        this.runtimeInterval = null; // Track runtime interval to avoid duplicates
        this.sessionStartTime = null; // Cache session start time
    }

    async init() {
        await this.loadAndRender();
        setInterval(() => this.loadAndRender(), this.updateInterval);
    }

    async loadAndRender() {
        try {
            const [metrics, tasks, events, session] = await Promise.all([
                this.fetchJSON('dashboard-metrics.json'),
                this.fetchJSON('task-queue.json'),
                this.fetchJSONL('events.jsonl'),
                this.fetchJSON('session.json')
            ]);

            this.renderHeader(session);
            this.renderStats(metrics);
            this.renderTasks(tasks);
            this.renderObservations(metrics?.system_health?.observations || []);
            this.renderToolCalls(events || []);
            this.renderEvents(events ? events.slice(-15) : []);
        } catch (error) {
            console.error('Error loading data:', error);
        }
    }

    async fetchJSON(file) {
        try {
            const response = await fetch(file);
            return response.ok ? response.json() : null;
        } catch (error) {
            console.error(`Error fetching ${file}:`, error);
            return null;
        }
    }

    async fetchJSONL(file) {
        try {
            const response = await fetch(file);
            if (!response.ok) return [];
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
        questionElement.textContent = session.research_question || 'Loading...';

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

            // Show report link (assumes research-report.md exists in session dir)
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
            <div class="task-item" style="font-size: 0.85em; padding: 8px 12px; margin-bottom: 6px; background: rgba(255,255,255,0.05); border-radius: 4px; display: flex; align-items: center;">
                <span style="margin-right: 8px; font-size: 1.2em;">${emoji}</span>
                <span style="flex: 1;"><strong style="color: #4a90e2;">${agent}</strong> - ${truncDesc}${newBadge}</span>
            </div>
        `;
    }

    renderObservations(observations) {
        const container = document.getElementById('health-container');

        if (!observations || observations.length === 0) {
            container.innerHTML = '<div class="empty-state">✓ No issues detected</div>';
            return;
        }

        // Group by severity for display order: critical, warning, info
        const criticalObs = observations.filter(o => o.data?.severity === 'critical');
        const warningObs = observations.filter(o => o.data?.severity === 'warning');
        const infoObs = observations.filter(o => o.data?.severity === 'info');
        const orderedObs = [...criticalObs, ...warningObs, ...infoObs];

        // Take top 10
        const displayObs = orderedObs.slice(0, 10);

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
            const agent = startEvent.data.agent || 'unknown';
            const summary = startEvent.data.input_summary || '';
            const timestamp = startEvent.timestamp;
            const startTime = new Date(timestamp).getTime();

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
            const truncSummary = call.summary.length > 35 ?
                call.summary.substring(0, 35) + '...' :
                call.summary;

            return `
                <div class="tool-item ${statusClass}" title="${this.escapeHtml(call.summary)}">
                    <div class="tool-header">
                        <span class="tool-name">${call.tool}</span>
                        <span class="tool-status ${statusIconClass}">${statusIcon}</span>
                    </div>
                    <div class="tool-details">${this.escapeHtml(truncSummary)}</div>
                    <div class="tool-footer">
                        <span>${call.agent}</span>
                        <span>${durationText || time}</span>
                    </div>
                </div>
            `;
        }).join('');
    }

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
            default:
                return `• ${event.type}`;
        }
    }
}

const dashboard = new Dashboard();
document.addEventListener('DOMContentLoaded', () => dashboard.init());

