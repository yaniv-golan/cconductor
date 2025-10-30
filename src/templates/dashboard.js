// Dashboard JavaScript - Real-time metrics
const AGENT_DISPLAY_MAP = {
    'mission-orchestrator': {
        icon: '🧭',
        title: 'Coordinating Research Step',
        type: 'analysis'
    },
    'research-planner': {
        icon: '🗂️',
        title: 'Research Strategy Planned',
        type: 'analysis'
    },
    'academic-researcher': {
        icon: '🔍',
        title: 'Searching Academic Literature',
        type: 'research'
    },
    'web-researcher': {
        icon: '🌐',
        title: 'Searching Web Sources',
        type: 'research'
    },
    'synthesis-agent': {
        icon: '✨',
        title: 'Synthesizing Findings',
        type: 'finding'
    },
    'research-coordinator': {
        icon: '🧭',
        title: 'Coordinating Research',
        type: 'analysis'
    },
    'quality-remediator': {
        icon: '🛡️',
        title: 'Quality Remediation',
        type: 'analysis'
    },
    'prompt-parser': {
        icon: '🧾',
        title: 'Prompt Parsed',
        type: 'analysis',
        formatter: () => 'Parsed the mission prompt and extracted structured objectives, constraints, and deliverables for downstream agents.'
    },
    'domain-heuristics': {
        icon: '🧭',
        title: 'Domain Heuristics Generated',
        type: 'analysis',
        formatter: () => 'Generated domain heuristics to guide stakeholder targeting, freshness expectations, and synthesis priorities.'
    },
    'stakeholder-classifier': {
        icon: '👥',
        title: 'Stakeholder Classification',
        type: 'analysis'
    }
};

class Dashboard {
    constructor() {
        this.updateInterval = 3000; // 3 seconds
        this.expandedJournalTasks = new Set(); // Track expanded journal entry breakdowns
        this.expandedJournalTools = new Set(); // Track expanded journal tools sections
        this.knownTaskIds = new Set(); // Track tasks (legacy renderTasks compatibility)
        this.newTaskIds = new Set(); // Track new tasks (legacy renderTasks compatibility)
        this.runtimeInterval = null; // Track runtime interval to avoid duplicates
        this.sessionStartTime = null; // Cache session start time
        this.sequenceHandlers = this.initializeSequenceHandlers();
        this.defaultSubtitles = {};
        this.sessionStatus = 'unknown';
        this.missionInProgress = true;
        const sessionFromBody = document.body?.dataset?.sessionId || '';
        this.sessionId = sessionFromBody || null;
        this.textFileExtensions = new Set(['json', 'jsonl', 'md', 'txt', 'log', 'yaml', 'yml']);

        this.handleFileLinkClick = this.handleFileLinkClick.bind(this);
        document.addEventListener('click', this.handleFileLinkClick);
    }

    initializeSequenceHandlers() {
        return [
            {
                startType: 'quality_gate_started',
                endType: 'quality_gate_completed',
                findMatch: (start, ends, used) => this.findQualityGateMatch(start, ends, used),
                buildEntry: (start, end) => this.buildQualityGateEntry(start, end),
                buildInProgress: start => this.buildQualityGateInProgress(start)
            },
            {
                startType: 'stakeholder_classifier_started',
                endType: 'stakeholder_classifier_completed',
                buildEntry: (start, end) => this.buildStakeholderClassifierEntry(start, end),
                buildInProgress: start => this.buildStakeholderClassifierInProgress(start)
            }
        ];
    }

    async init() {
        await this.loadAndRender();
        setInterval(() => this.loadAndRender(), this.updateInterval);
    }

    async loadAndRender() {
        try {
            const [metrics, events, session] = await Promise.all([
                this.fetchJSON('./dashboard-metrics.json'),
                this.fetchJSONL('../logs/events.jsonl'),
                this.fetchJSON('../meta/session.json')
            ]);

            // Store metrics for use in journal rendering (completion messages)
            this.currentMetrics = metrics;
            this.currentEvents = events || [];

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

        this.sessionStatus = session.status || 'unknown';
        const terminalStatuses = ['completed', 'completed_with_advisory', 'blocked_quality_gate', 'failed'];
        this.missionInProgress = !terminalStatuses.includes(this.sessionStatus);

        // Display clean objective (primary display)
        const questionElement = document.getElementById('research-question');
        const objectiveText = session.objective || session.research_question || 'Loading...';
        questionElement.textContent = objectiveText;

        // Setup expand/collapse for long questions
        this.setupQuestionToggle(objectiveText);

        // Show expandable full prompt if different from objective
        if (session.research_question && session.research_question !== session.objective) {
            // Remove any existing full prompt details
            const existingDetails = questionElement.parentNode.querySelector('.full-prompt-details');
            if (existingDetails) {
                existingDetails.remove();
            }
            
            const details = document.createElement('details');
            details.className = 'full-prompt-details';
            details.style.marginTop = '10px';
            details.style.fontSize = '0.9em';
            
            const summary = document.createElement('summary');
            summary.textContent = 'Show full user prompt';
            summary.style.cursor = 'pointer';
            summary.style.color = '#666';
            
            const content = document.createElement('div');
            content.style.marginTop = '8px';
            content.style.whiteSpace = 'pre-wrap';
            content.style.padding = '10px';
            content.style.backgroundColor = '#f5f5f5';
            content.style.borderRadius = '4px';
            content.textContent = session.research_question;
            
            details.appendChild(summary);
            details.appendChild(content);
            questionElement.parentNode.appendChild(details);
        }

        const sessionId = this.sessionId;
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

        if (!banner || !title || !message || !reportLink) return;

        banner.classList.remove('show', 'warning', 'error');
        reportLink.style.display = 'none';

        const completionEvent = this.currentEvents?.find(e =>
            e.type === 'research_complete' || e.type === 'mission_completed');
        const reportFile = completionEvent?.data?.report_file || 'report/mission-report.md';
        const qualityGate = session?.quality_gate || null;

        const stopRuntime = () => {
            if (this.runtimeInterval) {
                clearInterval(this.runtimeInterval);
                this.runtimeInterval = null;
            }
        };

        if (session.status === 'completed' || session.status === 'completed_with_advisory') {
            banner.classList.add('show');
            const completedTime = session.completed_at ?
                new Date(session.completed_at).toLocaleString() :
                'recently';

            const isAdvisory = session.status === 'completed_with_advisory' ||
                (qualityGate && qualityGate.status === 'failed' && (qualityGate.mode || 'advisory') === 'advisory');

            if (isAdvisory) {
                banner.classList.add('warning');
                title.textContent = '⚠ Research Complete with Advisory';
                const summaryRef = qualityGate?.summary_file
                    ? ` <a href="${qualityGate.summary_file}" target="_blank">View remediation summary</a>.`
                    : '';
                message.innerHTML = `Research session finished ${completedTime}. Quality gate flagged outstanding issues.${summaryRef}`;
            } else {
                title.textContent = '✅ Research Complete!';
                message.textContent = `Research session finished ${completedTime}`;
            }

            reportLink.href = reportFile;
            reportLink.style.display = 'inline-block';
            stopRuntime();

        } else if (session.status === 'blocked_quality_gate' || session.status === 'failed') {
            banner.classList.add('show', 'error');
            if (session.status === 'blocked_quality_gate') {
                title.textContent = '❌ Quality Gate Blocked Completion';
                const reportRef = qualityGate?.report_file
                    ? ` <a href="${qualityGate.report_file}" target="_blank">View diagnostic report</a>.`
                    : '';
                message.innerHTML = `Enforced quality checks failed—resolve the flagged issues and rerun.${reportRef}`;
            } else {
                title.textContent = '❌ Research Failed';
                message.textContent = session.error || 'Research encountered an error and could not complete.';
            }
            stopRuntime();
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

    cacheSubtitle(subtitleId) {
        if (!subtitleId || this.defaultSubtitles[subtitleId]) {
            return;
        }
        const subtitleEl = document.getElementById(subtitleId);
        if (subtitleEl) {
            this.defaultSubtitles[subtitleId] = subtitleEl.textContent;
        }
    }

    setMetricDisplay({
        valueId,
        subtitleId,
        value,
        formatValue,
        hint,
        readyCheck,
        onReady
    }) {
        const valueEl = document.getElementById(valueId);
        if (!valueEl) return;

        const subtitleEl = subtitleId ? document.getElementById(subtitleId) : null;
        if (subtitleId) {
            this.cacheSubtitle(subtitleId);
        }

        let numericValue = typeof value === 'number' ? value : Number(value);
        if (Number.isNaN(numericValue) || numericValue === null) {
            numericValue = 0;
        }

        const isReady = readyCheck ? readyCheck(value, numericValue) : (numericValue !== 0);
        const showPlaceholder = !isReady && this.missionInProgress;

        if (showPlaceholder) {
            valueEl.textContent = 'Not yet';
            valueEl.classList.add('placeholder');
            if (subtitleEl && hint) {
                subtitleEl.textContent = hint;
            }
            if (onReady) onReady(numericValue, true, subtitleEl);
        } else {
            const formattedValue = formatValue ? formatValue(numericValue) : `${numericValue}`;
            valueEl.textContent = formattedValue;
            valueEl.classList.remove('placeholder');
            const handled = onReady ? onReady(numericValue, false, subtitleEl) : false;
            if (!handled && subtitleEl && this.defaultSubtitles[subtitleId]) {
                subtitleEl.textContent = this.defaultSubtitles[subtitleId];
            }
        }
    }

    isLikelyFilePath(text) {
        if (!text) return false;
        const trimmed = text.trim();
        if (trimmed.length === 0) return false;
        if (trimmed.includes('*') || trimmed.includes('?')) return false;
        if (/^https?:\/\//i.test(trimmed)) return true;
        if (/^file:\/\//i.test(trimmed)) return true;
        if (trimmed.startsWith('/') || trimmed.startsWith('./') || trimmed.startsWith('../')) return true;
        if (trimmed.includes('research-sessions/')) return true;
        if (trimmed.includes('mission_')) return true;
        if (/[\\\/]/.test(trimmed) && /\.[A-Za-z0-9]+$/.test(trimmed)) return true;
        return false;
    }

    resolveSessionRelativePath(path) {
        if (!path) return null;
        let candidate = path.trim().replace(/\\/g, '/');
        if (candidate.length === 0) return null;

        if (/^https?:\/\//i.test(candidate) || /^file:\/\//i.test(candidate)) {
            return candidate;
        }

        if ((candidate.startsWith('"') && candidate.endsWith('"')) ||
            (candidate.startsWith("'") && candidate.endsWith("'"))) {
            candidate = candidate.slice(1, -1);
        }

        const missionRegex = /(mission|session)_\d{10,}/;
        const missionMatch = candidate.match(missionRegex);
        let sessionIdFromPath = missionMatch ? missionMatch[0] : null;

        if (sessionIdFromPath) {
            const index = candidate.indexOf(sessionIdFromPath);
            candidate = candidate.slice(index + sessionIdFromPath.length);
        }

        candidate = candidate.replace(/^[:]?/, '');
        candidate = candidate.replace(/^\/+/, '');

        while (candidate.startsWith('../')) {
            candidate = candidate.slice(3);
        }
        candidate = candidate.replace(/^\.\/+/, '');

        const lowered = candidate.toLowerCase();
        if (lowered === 'user-prompt.txt' || lowered === 'inputs/user-prompt.txt') {
            candidate = 'work/prompt-parser/input.txt';
        }

        if (!candidate) {
            candidate = 'viewer/index.html';
        }

        const sessionId = sessionIdFromPath || this.sessionId;
        if (!sessionId) {
            return candidate.startsWith('/') ? candidate : `/${candidate}`;
        }

        return `/${sessionId}/${candidate}`;
    }

    renderFileLink(original, display) {
        if (!original) {
            return this.escapeHtml(display || '');
        }

        if (!this.isLikelyFilePath(original)) {
            return this.escapeHtml(display || original);
        }

        const resolved = this.resolveSessionRelativePath(original);
        if (!resolved) {
            return this.escapeHtml(display || original);
        }

        const href = this.escapeAttribute(encodeURI(resolved));
        const label = display || original;

        return `<a href="${href}" target="_blank" rel="noopener noreferrer" data-file-link="1">${this.escapeHtml(label)}</a>`;
    }

    renderStats(metrics) {
        if (!metrics) {
            // Show loading indicator if metrics don't exist yet
            this.showLoadingState();
            return;
        }
        
        // Remove loading indicator if it exists
        this.hideLoadingState();

        this.setMetricDisplay({
            valueId: 'stat-iteration',
            subtitleId: 'stat-iteration-subtitle',
            value: metrics.iteration || 0,
            formatValue: val => `${val}`,
            hint: 'Starts after the first orchestration loop.'
        });

        this.setMetricDisplay({
            valueId: 'stat-confidence',
            subtitleId: 'stat-confidence-subtitle',
            value: metrics.confidence || 0,
            formatValue: val => `${Math.round(val * 100)}%`,
            hint: 'Appears once knowledge graph scoring runs.',
            readyCheck: () => (metrics.iteration || 0) > 0 || (metrics.confidence || 0) !== 0
        });

        this.setMetricDisplay({
            valueId: 'stat-entities',
            subtitleId: 'stat-entities-subtitle',
            value: metrics.knowledge?.entities || 0,
            formatValue: val => `${val}`,
            hint: 'Populates after researchers add new entities.',
            readyCheck: () => (metrics.iteration || 0) > 0 || (metrics.knowledge?.entities || 0) !== 0
        });

        this.setMetricDisplay({
            valueId: 'stat-claims',
            subtitleId: 'stat-claims-subtitle',
            value: metrics.knowledge?.claims || 0,
            formatValue: val => `${val}`,
            hint: 'Populates after evidence is synthesized.',
            readyCheck: () => (metrics.iteration || 0) > 0 || (metrics.knowledge?.claims || 0) !== 0
        });

        this.setMetricDisplay({
            valueId: 'stat-cost',
            subtitleId: 'stat-cost-subtitle',
            value: metrics.costs?.total_usd || 0,
            formatValue: val => `$${val.toFixed(2)}`,
            hint: 'Costs appear once agents invoke tools.',
            readyCheck: () => (metrics.progress?.completed_invocations || 0) > 0 || (metrics.costs?.total_usd || 0) !== 0,
            onReady: (val, placeholder, subtitleEl) => {
                if (!subtitleEl) {
                    return false;
                }
                if (placeholder) {
                    subtitleEl.textContent = 'Will estimate per iteration once agents complete.';
                    return true;
                }
                const perIteration = metrics.costs?.per_iteration || 0;
                subtitleEl.textContent = `$${perIteration.toFixed(2)} per iteration`;
                return true;
            }
        });

        const preflight = metrics.preflight || {};
        const preflightHeuristics = preflight.domain_heuristics_runs || 0;
        const preflightPrompt = preflight.prompt_parser_runs || 0;
        const preflightStakeholders = preflight.stakeholder_classifications || 0;
        const preflightTotal = preflightHeuristics + preflightPrompt + preflightStakeholders;
        const preflightCard = document.getElementById('preflight-card');

        if (preflightCard) {
            if (preflightTotal > 0 || this.missionInProgress) {
                preflightCard.style.display = '';
                const heuristicsEl = document.getElementById('preflight-heuristics-count');
                const promptEl = document.getElementById('preflight-prompt-count');
                const stakeholdersEl = document.getElementById('preflight-stakeholders-count');
                const subtitleEl = document.getElementById('preflight-subtitle');

                const setPreflightValue = (el, count) => {
                    if (!el) return;
                    const showPlaceholder = count === 0 && this.missionInProgress;
                    el.textContent = showPlaceholder ? 'Not yet' : `${count}`;
                    el.classList.toggle('placeholder', showPlaceholder);
                };

                setPreflightValue(heuristicsEl, preflightHeuristics);
                setPreflightValue(promptEl, preflightPrompt);
                setPreflightValue(stakeholdersEl, preflightStakeholders);

                if (subtitleEl) {
                    if (preflightTotal > 0) {
                        subtitleEl.textContent = `${preflightTotal} early checks recorded`;
                    } else if (this.missionInProgress) {
                        subtitleEl.textContent = 'Early checks will appear as setup agents complete.';
                    } else {
                        subtitleEl.textContent = 'No preflight activity recorded.';
                    }
                }
            } else {
                preflightCard.style.display = 'none';
            }
        }

        // Runtime is now calculated dynamically in startLiveRuntime() for live updates
        // No need to set it here - it updates every second automatically
    }
    
    showLoadingState() {
        const statElements = [
            'stat-iteration',
            'stat-confidence', 
            'stat-entities',
            'stat-claims',
            'stat-cost'
        ];
        
        statElements.forEach(id => {
            const el = document.getElementById(id);
            if (el && (el.textContent === '0' || el.textContent === '0%' || el.textContent === '0.00')) {
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
            const detailHtml = this.renderFileLink(call.summary, truncSummary);

            return `
                <div class="tool-item ${statusClass}" title="${this.escapeHtml(call.summary)}">
                    <span class="tool-icon">${this.getToolIcon(call.tool)}</span>
                    <div class="tool-content">
                        <div class="tool-header">
                            <span class="tool-name">${friendlyToolName}</span>
                            <span class="tool-status ${statusIconClass}">${statusIcon}</span>
                        </div>
                        <div class="tool-details">${detailHtml}</div>
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

        if (!events || events.length === 0) {
            return entries;
        }

        const sessionCreated = events.find(e => e.type === 'session_created' || e.type === 'mission_started');
        if (sessionCreated && this.isValidTimestamp(sessionCreated.timestamp)) {
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

        const orderedAgents = this.buildOrderedAgents(events);
        orderedAgents.forEach(agentName => {
            const invocations = events.filter(e => e.type === 'agent_invocation' && e.data.agent === agentName);
            const results = events.filter(e => e.type === 'agent_result' && e.data.agent === agentName);
            const pairCount = Math.min(invocations.length, results.length);

            for (let i = 0; i < pairCount; i++) {
                const invocation = invocations[i];
                const result = results[i];
                const startTime = invocation?.timestamp || result?.timestamp || null;
                const endTime = result?.timestamp || null;
                const resultData = result?.data || {};

                if (!this.isValidTimestamp(startTime)) {
                    continue;
                }

                entries.push({
                    type: this.getEntryType(agentName),
                    icon: this.getAgentIcon(agentName),
                    title: this.getAgentTitle(agentName),
                    startTime,
                    endTime: this.isValidTimestamp(endTime) ? endTime : null,
                    content: this.formatAgentWork(agentName, resultData),
                    agent: agentName,
                    metadata: {
                        duration: this.calculateDurationSeconds(invocation?.timestamp, result?.timestamp),
                        cost: resultData.cost_usd || 0,
                        ...resultData
                    },
                    events: [invocation, result],
                    tasks: this.getTasksForAgent(agentName, events),
                    tools: this.getToolsForAgent(agentName, events, startTime, endTime)
                });
            }
        });

        events.filter(e => e.type === 'iteration_complete' && this.isValidTimestamp(e.timestamp)).forEach(e => {
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

        const researchComplete = events.find(e => (e.type === 'research_complete' || e.type === 'mission_completed') && this.isValidTimestamp(e.timestamp));
        if (researchComplete) {
            const reportFile = researchComplete.data?.report_file || 'report/mission-report.md';
            const completionData = researchComplete.type === 'mission_completed'
                ? {
                    claims_synthesized: this.currentMetrics?.knowledge?.claims || 0,
                    entities_integrated: this.currentMetrics?.knowledge?.entities || 0,
                    report_sections: this.currentMetrics?.report?.sections || 0,
                    report_file: reportFile
                }
                : researchComplete.data || {};

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

        entries.push(...this.processSequenceEventHandlers(events));

        orderedAgents.forEach(agentName => {
            const invocations = events.filter(e => e.type === 'agent_invocation' && e.data.agent === agentName);
            const results = events.filter(e => e.type === 'agent_result' && e.data.agent === agentName);
            if (invocations.length > results.length) {
                const inProgressInvocation = invocations[invocations.length - 1];
                if (!this.isValidTimestamp(inProgressInvocation?.timestamp)) {
                    return;
                }
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
                    tasks: this.getTasksForAgent(agentName, events),
                    tools: []
                });
            }
        });

        const taskStarts = events.filter(e => e.type === 'task_started');
        const taskEnds = events.filter(e => e.type === 'task_completed' || e.type === 'task_failed');
        const taskEndIds = new Set(taskEnds.map(e => e.data.task_id));

        taskStarts.forEach(taskStart => {
            if (taskEndIds.has(taskStart.data.task_id) || !this.isValidTimestamp(taskStart.timestamp)) {
                return;
            }
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
        });

        const validEntries = entries.filter(entry => this.isValidTimestamp(entry.startTime));
        return validEntries.sort((a, b) => this.parseTimestamp(b.startTime) - this.parseTimestamp(a.startTime));
    }


    buildOrderedAgents(events) {
        const agentEvents = (events || []).filter(e =>
            (e.type === 'agent_invocation' || e.type === 'agent_result') &&
            e.data && e.data.agent
        );
        const discovered = [...new Set(agentEvents.map(e => e.data.agent))];
        const preferredOrder = [
            'mission-orchestrator',
            'domain-heuristics',
            'prompt-parser',
            'research-planner',
            'academic-researcher',
            'web-researcher',
            'stakeholder-classifier',
            'research-coordinator',
            'synthesis-agent',
            'quality-remediator'
        ];
        return [
            ...preferredOrder.filter(agent => discovered.includes(agent)),
            ...discovered.filter(agent => !preferredOrder.includes(agent))
        ];
    }

    processSequenceEventHandlers(events) {
        const sequenceEntries = [];
        this.sequenceHandlers.forEach(handler => {
            const starts = events.filter(e => e.type === handler.startType);
            const ends = events.filter(e => e.type === handler.endType);
            const usedEnds = new Set();

            starts.forEach(start => {
                let match;
                if (typeof handler.findMatch === 'function') {
                    match = handler.findMatch(start, ends, usedEnds);
                } else {
                    match = this.findDefaultSequenceMatch(start, ends, usedEnds);
                }

                if (match) {
                    usedEnds.add(match);
                    if (typeof handler.buildEntry === 'function') {
                        sequenceEntries.push(handler.buildEntry(start, match));
                    }
                } else if (typeof handler.buildInProgress === 'function') {
                    sequenceEntries.push(handler.buildInProgress(start));
                }
            });
        });
        return sequenceEntries;
    }

    findDefaultSequenceMatch(start, ends, usedEnds) {
        const startTime = this.parseTimestamp(start?.timestamp);
        return ends.find(end => {
            if (usedEnds.has(end)) {
                return false;
            }
            const endTime = this.parseTimestamp(end?.timestamp);
            if (startTime !== null && endTime !== null && endTime < startTime) {
                return false;
            }
            return true;
        }) || null;
    }

    findQualityGateMatch(start, ends, usedEnds) {
        const startTime = this.parseTimestamp(start?.timestamp);
        const attempt = start?.data?.attempt ?? null;
        return ends.find(end => {
            if (usedEnds.has(end)) {
                return false;
            }
            const endAttempt = end?.data?.attempt ?? null;
            if (attempt !== null && endAttempt !== attempt) {
                return false;
            }
            const endTime = this.parseTimestamp(end?.timestamp);
            if (startTime !== null && endTime !== null && endTime < startTime) {
                return false;
            }
            return true;
        }) || null;
    }

    buildQualityGateEntry(start, end) {
        const attempt = end?.data?.attempt ?? start?.data?.attempt ?? 1;
        const status = end?.data?.status || 'unknown';
        const passed = status === 'passed';
        return {
            type: passed ? 'milestone' : 'warning',
            icon: passed ? '🛡️' : '⚠️',
            title: passed ? `Quality Gate Passed (Attempt ${attempt})` : `Quality Gate Flagged Issues (Attempt ${attempt})`,
            startTime: start?.timestamp || null,
            endTime: end?.timestamp || null,
            content: this.formatQualityGateContent(end?.data || start?.data || {}),
            agent: 'quality-gate',
            metadata: end?.data || {},
            events: [start, end],
            tasks: [],
            tools: []
        };
    }

    buildQualityGateInProgress(start) {
        const attempt = start?.data?.attempt ?? 1;
        return {
            type: 'in_progress',
            icon: '🛡️',
            title: `Quality Gate Running (Attempt ${attempt})`,
            startTime: start?.timestamp || null,
            endTime: null,
            content: 'Evaluating claims against trust, recency, and coverage thresholds...',
            agent: 'quality-gate',
            metadata: start?.data || {},
            events: [start],
            tasks: [],
            tools: []
        };
    }

    buildStakeholderClassifierEntry(start, end) {
        const startData = start?.data || {};
        const endData = end?.data || {};
        const startTime = start?.timestamp || startData.started_at || null;
        const endTime = end?.timestamp || endData.completed_at || null;
        return {
            type: this.getEntryType('stakeholder-classifier'),
            icon: this.getAgentIcon('stakeholder-classifier'),
            title: 'Stakeholder Classification Completed',
            startTime,
            endTime: this.isValidTimestamp(endTime) ? endTime : null,
            content: this.formatStakeholderClassifierContent(startData, endData),
            agent: 'stakeholder-classifier',
            metadata: {
                total_sources: endData.total_sources ?? startData.total_sources ?? 0,
                classifications: endData.classifications ?? 0,
                needs_review: endData.needs_review ?? 0,
                pending_sources: endData.pending_sources ?? 0
            },
            events: [start, end],
            tasks: [],
            tools: []
        };
    }

    buildStakeholderClassifierInProgress(start) {
        const startData = start?.data || {};
        const sources = startData.total_sources ?? 0;
        return {
            type: 'in_progress',
            icon: this.getAgentIcon('stakeholder-classifier'),
            title: 'Stakeholder Classification Running',
            startTime: start?.timestamp || startData.started_at || null,
            endTime: null,
            content: `Classifying ${sources} knowledge graph source${sources === 1 ? '' : 's'}...`,
            agent: 'stakeholder-classifier',
            metadata: {
                total_sources: sources,
                status: 'running'
            },
            events: [start],
            tasks: [],
            tools: []
        };
    }

    formatStakeholderClassifierContent(startData, endData) {
        const total = endData.total_sources ?? startData.total_sources ?? 0;
        const classified = endData.classifications ?? 0;
        const needs = endData.needs_review ?? 0;
        const pending = endData.pending_sources ?? 0;

        let message = `Classified ${classified} source${classified === 1 ? '' : 's'} out of ${total}.`;
        if (needs > 0) {
            message += ` Flagged ${needs} for review.`;
        }
        if (pending > 0) {
            message += ` ${pending} source${pending === 1 ? '' : 's'} pending.`;
        }
        return message;
    }

    isValidTimestamp(timestamp) {
        return this.parseTimestamp(timestamp) !== null;
    }

    parseTimestamp(timestamp) {
        if (!timestamp) {
            return null;
        }
        const value = Date.parse(timestamp);
        if (Number.isNaN(value)) {
            return null;
        }
        return value;
    }

    getEntryType(agentName) {
        const config = AGENT_DISPLAY_MAP[agentName];
        if (config?.type) {
            return config.type;
        }
        const types = {
            'research-planner': 'analysis',
            'academic-researcher': 'research',
            'web-researcher': 'research',
            'synthesis-agent': 'finding',
            'research-coordinator': 'analysis',
            'quality-remediator': 'analysis'
        };
        return types[agentName] || 'research';
    }

    getAgentIcon(agentName) {
        const config = AGENT_DISPLAY_MAP[agentName];
        if (config?.icon) {
            return config.icon;
        }
        const icons = {
            'research-planner': '🗂️',
            'academic-researcher': '🔍',
            'web-researcher': '🌐',
            'synthesis-agent': '✨',
            'research-coordinator': '🧭',
            'quality-remediator': '🛡️'
        };
        return icons[agentName] || '🤖';
    }

    getAgentTitle(agentName) {
        const config = AGENT_DISPLAY_MAP[agentName];
        if (config?.title) {
            return config.title;
        }
        const titles = {
            'mission-orchestrator': 'Coordinating Research Step',
            'research-planner': 'Research Strategy Planned',
            'academic-researcher': 'Searching Academic Literature',
            'web-researcher': 'Searching Web Sources',
            'synthesis-agent': 'Synthesizing Findings',
            'research-coordinator': 'Coordinating Research',
            'quality-remediator': 'Quality Remediation'
        };
        return titles[agentName] || 'Working';
    }

    formatAgentWork(agentName, resultData) {
        const data = resultData || {};
        const mapFormatter = AGENT_DISPLAY_MAP[agentName]?.formatter;
        if (typeof mapFormatter === 'function') {
            return mapFormatter(data);
        }

        const templates = {
            'research-planner': () => {
                const tasks = data.tasks_generated || 0;
                return `I analyzed the query and identified ${tasks} critical research area${tasks !== 1 ? 's' : ''} to explore.`;
            },
            'academic-researcher': () => {
                const papers = data.papers_found || 0;
                const searches = data.searches_performed || 0;
                return `I conducted ${searches} systematic search${searches !== 1 ? 'es' : ''} across academic databases and found ${papers} relevant paper${papers !== 1 ? 's' : ''} with focus on peer-reviewed sources.`;
            },
            'web-researcher': () => {
                const sources = data.sources_found || 0;
                const searches = data.searches_performed || 0;
                return `I performed ${searches} web search${searches !== 1 ? 'es' : ''} and analyzed ${sources} source${sources !== 1 ? 's' : ''} to gather current information on the research topic.`;
            },
            'synthesis-agent': () => {
                const claims = data.claims_synthesized || 0;
                const gaps = data.gaps_found || 0;
                return `I synthesized ${claims} claim${claims !== 1 ? 's' : ''} from all gathered sources and identified ${gaps} knowledge gap${gaps !== 1 ? 's' : ''} requiring further investigation.`;
            },
            'quality-remediator': () => {
                return 'I reviewed the quality gate diagnostics and gathered additional evidence for the flagged claims. See work/quality-remediator/ for remediation notes.';
            },
            'research-coordinator': () => {
                const entities = data.entities_discovered || 0;
                const claims = data.claims_validated || 0;
                const gaps = data.gaps_identified || 0;
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
        const reportFile = data.report_file || 'report/mission-report.md';
        
        // Build message based on whether we have section count
        const sectionText = sections > 0 
            ? `with ${sections} section${sections !== 1 ? 's' : ''}, ` 
            : '';
        
        return `I synthesized all research findings into a comprehensive report ${sectionText}integrating ${claims} claim${claims !== 1 ? 's' : ''} and ${entities} entit${entities !== 1 ? 'ies' : 'y'}. 
        
📄 <strong><a href="${reportFile}" target="_blank">View Research Report</a></strong>

📖 <strong><a href="report/research-journal.md" target="_blank">View Research Journal</a></strong> (Sequential timeline with full details)`;
    }

    formatQualityGateContent(data) {
        const status = data?.status || 'running';
        const mode = (data?.mode || 'advisory').toUpperCase();
        const summaryLink = data?.summary_file ? `<a href="${data.summary_file}" target="_blank">Summary</a>` : null;
        const reportLink = data?.report_file ? `<a href="${data.report_file}" target="_blank">Full diagnostics</a>` : null;
        let base;

        if (status === 'passed') {
            base = `Quality gate passed (${mode} mode).`;
        } else if (status === 'failed') {
            base = `Quality gate flagged issues (${mode} mode).`;
            if (mode === 'ADVISORY') {
                base += ' Issues are advisory and do not block completion.';
            }
        } else {
            base = `Quality gate evaluation running (${mode} mode).`;
        }

        const links = [summaryLink, reportLink].filter(Boolean).join(' · ');
        if (links) {
            base += ` ${links}`;
        }

        return base;
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
        const startMs = this.parseTimestamp(startTime);
        const endMs = this.parseTimestamp(endTime);

        if (startMs === null || endMs === null) {
            return tools;
        }

        const toolStarts = events.filter(e =>
            e.type === 'tool_use_start' &&
            e.data.agent === agentName &&
            this.parseTimestamp(e.timestamp) !== null &&
            this.parseTimestamp(e.timestamp) >= startMs &&
            this.parseTimestamp(e.timestamp) <= endMs
        );

        toolStarts.forEach(start => {
            const tool = start.data.tool;
            const startToolTime = this.parseTimestamp(start.timestamp);
            if (startToolTime === null) {
                return;
            }

            const complete = events.find(e => {
                if (e.type !== 'tool_use_complete' || e.data.tool !== tool) {
                    return false;
                }
                const completeTime = this.parseTimestamp(e.timestamp);
                if (completeTime === null) {
                    return false;
                }
                return completeTime > startToolTime && completeTime <= endMs && (completeTime - startToolTime) < 60000;
            });

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
            
            const detailHtml = this.renderFileLink(tool.details, truncDetails);

            return `
                <div class="tool-used-item ${tool.status}">
                    <span class="tool-used-icon">${tool.icon}</span>
                    <span class="tool-used-name">${tool.tool}</span>
                    <span class="tool-used-details" title="${this.escapeHtml(tool.details)}">${detailHtml}</span>
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
        const parsed = this.parseTimestamp(timestamp);
        if (parsed === null) {
            return '--:--:--';
        }
        return new Date(parsed).toLocaleTimeString('en-US', { 
            hour: '2-digit', 
            minute: '2-digit',
            second: '2-digit',
            hour12: false 
        });
    }

    calculateDurationSeconds(startTime, endTime) {
        const start = this.parseTimestamp(startTime);
        const end = this.parseTimestamp(endTime);
        if (start === null || end === null) {
            return 0;
        }
        const delta = Math.round((end - start) / 1000);
        return delta < 0 ? 0 : delta;
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

    escapeAttribute(value) {
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    shouldStreamInline(extension) {
        if (!extension) return false;
        return this.textFileExtensions.has(extension.toLowerCase());
    }

    formatFetchedText(text, extension) {
        const ext = (extension || '').toLowerCase();
        if (ext === 'json') {
            try {
                const parsed = JSON.parse(text);
                return JSON.stringify(parsed, null, 2);
            } catch (error) {
                console.warn('Failed to pretty-print JSON file', error);
                return text;
            }
        }

        if (ext === 'jsonl') {
            const lines = text.split(/\r?\n/);
            const formatted = [];
            const failures = [];
            lines.forEach((line, index) => {
                const trimmed = line.trim();
                if (!trimmed) {
                    formatted.push(line);
                    return;
                }
                try {
                    const parsedLine = JSON.parse(trimmed);
                    formatted.push(JSON.stringify(parsedLine, null, 2));
                } catch (error) {
                    failures.push(index + 1);
                    formatted.push(line);
                }
            });
            if (failures.length > 0) {
                console.warn(`Failed to pretty-print ${failures.length} JSONL lines: ${failures.join(', ')}`);
            }
            return formatted.join('\n\n');
        }

        return text;
    }

    // Some Chromium- and WebKit-based browsers refuse to display text/plain files opened via
    // window.open from intercepted links, leaving users on about:blank. Fetching the content and
    // streaming it through a blob URL keeps the UX consistent across Chrome, Edge, and Safari while
    // also letting us pretty-print structured text like JSON.
    async openTextFileInNewTab(url, extension = '', fallbackTarget = '_blank') {
        try {
            const response = await fetch(url, { cache: 'no-store' });
            if (!response.ok) {
                window.open(url, fallbackTarget, 'noopener');
                return;
            }
            const text = await response.text();
            const normalizedExtension = (extension || '').toLowerCase();
            const formatted = this.formatFetchedText(text, normalizedExtension);
            const mimeType = normalizedExtension === 'json'
                ? 'application/json;charset=utf-8'
                : 'text/plain;charset=utf-8';
            const blob = new Blob([formatted], { type: mimeType });
            const blobUrl = URL.createObjectURL(blob);
            const opened = window.open(blobUrl, fallbackTarget, 'noopener');
            if (opened) {
                setTimeout(() => URL.revokeObjectURL(blobUrl), 60_000);
            } else {
                URL.revokeObjectURL(blobUrl);
                window.open(url, fallbackTarget, 'noopener');
            }
        } catch (error) {
            console.error('Failed to stream file, falling back to default behavior', error);
            window.open(url, fallbackTarget, 'noopener');
        }
    }

    handleFileLinkClick(event) {
        const link = event.target.closest('a[data-file-link="1"]');
        if (!link) {
            return;
        }

        const url = link.href;
        let extension = '';
        try {
            const withoutQuery = url.split('#')[0].split('?')[0];
            const parts = withoutQuery.split('.');
            extension = parts.length > 1 ? parts.pop() : '';
        } catch (err) {
            extension = '';
        }

        if (!this.shouldStreamInline(extension)) {
            return;
        }

        event.preventDefault();
        this.openTextFileInNewTab(url, extension, link.target || '_blank');
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
                const reportFile = event.data.report_file || 'report/mission-report.md';
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
            case 'quality_gate_started':
                return `🛡️ Quality gate attempt ${event.data?.attempt || 1} started (${(event.data?.mode || 'advisory').toUpperCase()})`;
            case 'quality_gate_completed':
                const gateStatus = event.data?.status || 'completed';
                const gateIcon = gateStatus === 'passed' ? '✅' : '⚠️';
                return `${gateIcon} Quality gate ${gateStatus} (attempt ${event.data?.attempt || 1})`;
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
        const kg = await this.fetchJSON('../knowledge/knowledge-graph.json');
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
        const kg = await this.fetchJSON('../knowledge/knowledge-graph.json');
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
