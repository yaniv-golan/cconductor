// Dashboard JavaScript - Real-time metrics
class Dashboard {
    constructor() {
        this.updateInterval = 3000; // 3 seconds
        this.expandedEvents = new Set(); // Track expanded event indices
        this.knownTaskIds = new Set(); // Track tasks we've seen before
        this.newTaskIds = new Set(); // Track newly added tasks
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
            return text.trim().split('\n')
                .filter(line => line.trim())
                .map(line => JSON.parse(line));
        } catch (error) {
            console.error(`Error fetching ${file}:`, error);
            return [];
        }
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
    }

    renderStats(metrics) {
        if (!metrics) return;

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

        const elapsed = metrics.runtime?.elapsed_seconds || 0;
        const mins = Math.floor(elapsed / 60);
        const hours = Math.floor(mins / 60);
        const secs = elapsed % 60;
        
        let runtimeText;
        if (hours > 0) {
            runtimeText = `${hours}h ${mins % 60}m`;
        } else if (mins > 0) {
            runtimeText = `${mins}m ${secs}s`;
        } else {
            runtimeText = `${secs}s`;
        }
        document.getElementById('stat-runtime').textContent = runtimeText;
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

    renderToolCalls(events) {
        if (!events || events.length === 0) return;

        const container = document.getElementById('tools-container');

        // Filter for tool use events and group by tool_use_start
        const toolCalls = [];
        const toolStarts = events.filter(e => e.type === 'tool_use_start');

        // For each tool start, find its corresponding complete event
        toolStarts.forEach(startEvent => {
            const tool = startEvent.data.tool;
            const agent = startEvent.data.agent || 'unknown';
            const summary = startEvent.data.input_summary || '';
            const timestamp = startEvent.timestamp;

            // Find corresponding complete event (within 60s)
            const completeEvent = events.find(e =>
                e.type === 'tool_use_complete' &&
                e.data.tool === tool &&
                Math.abs(new Date(e.timestamp) - new Date(timestamp)) < 60000
            );

            const duration = completeEvent ? completeEvent.data.duration_ms : null;
            const status = completeEvent ? completeEvent.data.status : 'pending';

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
            const time = new Date(call.timestamp).toLocaleTimeString();
            const statusClass = call.status === 'success' ? 'tool-status-success' : 'tool-status-failed';
            const statusIcon = call.status === 'success' ? '✓' : (call.status === 'failed' ? '✗' : '⏳');

            let durationText = '';
            if (call.duration !== null) {
                if (call.duration > 1000) {
                    durationText = `${(call.duration / 1000).toFixed(1)}s`;
                } else {
                    durationText = `${call.duration}ms`;
                }
            }

            // Truncate summary
            const truncSummary = call.summary.length > 50 ?
                call.summary.substring(0, 50) + '...' :
                call.summary;

            return `
                <div class="tool-item">
                    <span class="tool-name">${call.tool}</span>
                    <span class="tool-details" title="${this.escapeHtml(call.summary)}">${truncSummary}</span>
                    <span class="${statusClass}">${statusIcon}</span>
                    ${durationText ? `<span class="tool-duration">${durationText}</span>` : ''}
                </div>
            `;
        }).join('');
    }

    renderEvents(events) {
        if (!events || events.length === 0) return;

        const container = document.getElementById('events-container');
        container.innerHTML = events.reverse().map((event, index) => {
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
            default:
                return `• ${event.type}`;
        }
    }
}

const dashboard = new Dashboard();
document.addEventListener('DOMContentLoaded', () => dashboard.init());

