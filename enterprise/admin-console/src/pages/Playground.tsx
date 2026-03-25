import { useState, useEffect, useCallback, useMemo } from 'react';
import { Send, User, Bot, Shield, Eye, Terminal, Loader } from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import { Card, Badge, Button, PageHeader, Select } from '../components/ui';
import { usePlaygroundProfiles, useAgents, useEmployees, usePositions } from '../hooks/useApi';
import { api } from '../api/client';

const STORAGE_KEY = 'openclaw_playground_chat';

function loadMessages(tenantId: string): ChatMessage[] {
  try {
    const raw = localStorage.getItem(`${STORAGE_KEY}_${tenantId}`);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveMessages(tenantId: string, messages: ChatMessage[]) {
  localStorage.setItem(`${STORAGE_KEY}_${tenantId}`, JSON.stringify(messages));
}

interface ChatMessage { role: 'user' | 'assistant' | 'system'; content: string; timestamp: string; }

export default function Playground() {
  const { data: profiles } = usePlaygroundProfiles();
  const { data: agents = [] } = useAgents();
  const { data: employees = [] } = useEmployees();
  const { data: positions = [] } = usePositions();

  // Build tenant options from real employees + agents
  const tenantOptions = useMemo(() => {
    const opts = employees
      .filter(e => e.agentId)
      .map(e => ({
        label: `${e.name} — ${e.positionName}`,
        value: `port__${e.id}`,
      }));
    if (opts.length === 0) {
      return [
        { label: 'Carol Zhang — Finance Analyst', value: 'port__emp-carol' },
        { label: 'Wang Wu — Software Engineer', value: 'port__emp-w5' },
        { label: 'Zhang San — Solutions Architect', value: 'port__emp-z3' },
      ];
    }
    return opts;
  }, [employees]);

  const [tenantId, setTenantId] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputValue, setInputValue] = useState('');
  const [lastPlanE, setLastPlanE] = useState('No messages processed yet');
  const [mode, setMode] = useState<'simulate' | 'live'>('simulate');
  const [sending, setSending] = useState(false);

  // Initialize tenantId when options load
  useEffect(() => {
    if (tenantOptions.length > 0 && !tenantId) {
      setTenantId(tenantOptions[0].value);
    }
  }, [tenantOptions, tenantId]);

  const profile = profiles?.[tenantId] || { role: 'loading', tools: [], planA: '', planE: '' };
  const profileLoaded = !!profiles?.[tenantId];

  // Persist messages — but skip when tenant is switching (avoid saving old messages to new key)
  const [tenantReady, setTenantReady] = useState(false);
  useEffect(() => { if (tenantId && tenantReady) saveMessages(tenantId, messages); }, [messages]);

  useEffect(() => {
    if (!tenantId) return;
    setTenantReady(false);
    const saved = loadMessages(tenantId);
    if (saved.length > 0) {
      setMessages(saved);
    } else {
      const p = profiles?.[tenantId];
      const label = tenantOptions.find(o => o.value === tenantId)?.label || tenantId;
      setMessages([{ role: 'system', content: `🔒 Tenant context loaded: ${label} — ${p?.role || 'unknown'} role, ${p?.tools?.length || 0} tools`, timestamp: '' }]);
    }
    setLastPlanE('No messages processed yet');
    // Allow persistence after load completes
    setTimeout(() => setTenantReady(true), 100);
  }, [tenantId, profiles]);

  const handleSend = async () => {
    if (!inputValue.trim() || sending) return;
    const now = new Date().toLocaleTimeString();
    const msg = inputValue.trim();
    const userMsg: ChatMessage = { role: 'user', content: msg, timestamp: now };
    setMessages(prev => [...prev, userMsg]);
    setInputValue('');
    setSending(true);

    try {
      const data = await api.post<{ response: string; plan_e: string }>('/playground/send', { tenant_id: tenantId, message: msg, mode });
      setMessages(prev => [...prev, { role: 'assistant', content: data.response, timestamp: new Date().toLocaleTimeString() }]);
      setLastPlanE(data.plan_e);
    } catch (e) {
      if (mode === 'live') {
        setMessages(prev => [...prev, { role: 'assistant', content: '⏳ Agent is warming up (cold start ~25s). Retrying...', timestamp: new Date().toLocaleTimeString() }]);
        // Retry after 5s
        try {
          await new Promise(r => setTimeout(r, 5000));
          const retry = await api.post<{ response: string; plan_e: string }>('/playground/send', { tenant_id: tenantId, message: msg, mode });
          setMessages(prev => [...prev, { role: 'assistant', content: retry.response, timestamp: new Date().toLocaleTimeString() }]);
          setLastPlanE(retry.plan_e);
        } catch {
          setMessages(prev => [...prev, { role: 'assistant', content: 'Agent is still starting up. Please try again in ~30 seconds.', timestamp: new Date().toLocaleTimeString() }]);
        }
      } else {
        setMessages(prev => [...prev, { role: 'assistant', content: '⚠️ Error communicating with agent', timestamp: new Date().toLocaleTimeString() }]);
      }
    } finally {
      setSending(false);
    }
  };

  return (
    <div>
      <PageHeader title="Agent Playground" description="Test agent behavior with different tenant contexts and permission profiles" />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <Card>
          <div className="mb-4 space-y-3">
            <Select label="Tenant Context" value={tenantId} onChange={v => setTenantId(v)} options={tenantOptions} />
            <div className="flex items-center gap-3">
              <span className="text-xs text-text-muted">Mode:</span>
              <button onClick={() => setMode('simulate')} className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${mode === 'simulate' ? 'bg-primary/10 text-primary-light' : 'text-text-muted hover:bg-dark-hover'}`}>Simulate</button>
              <button onClick={() => setMode('live')} className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${mode === 'live' ? 'bg-success/10 text-success' : 'text-text-muted hover:bg-dark-hover'}`}>🔴 Live (AgentCore)</button>
            </div>
          </div>

          <div className="min-h-[350px] max-h-[450px] overflow-y-auto rounded-lg bg-dark-bg border border-dark-border p-4 mb-4 space-y-3">
            {messages.map((msg, i) => (
              <div key={i} className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                <div className={`max-w-[85%] rounded-lg px-3 py-2 ${
                  msg.role === 'user' ? 'bg-primary/15 text-text-primary'
                  : msg.role === 'system' ? 'bg-dark-hover text-text-muted text-xs'
                  : 'bg-dark-card border border-dark-border text-text-primary'
                }`}>
                  <div className="flex items-center gap-1.5 mb-1">
                    {msg.role === 'system' ? <Terminal size={12} /> : msg.role === 'user' ? <User size={12} /> : <Bot size={12} />}
                    <span className="text-xs text-text-muted">
                      {msg.role === 'system' ? 'System' : msg.role === 'user' ? 'You' : 'Agent'}
                      {msg.timestamp && ` · ${msg.timestamp}`}
                    </span>
                  </div>
                  {msg.role === 'assistant' ? (
                    <div className="text-sm prose prose-invert prose-sm max-w-none [&_p]:my-1 [&_h1]:text-base [&_h1]:font-bold [&_h2]:text-sm [&_h2]:font-semibold [&_ul]:my-1 [&_ol]:my-1 [&_li]:my-0.5 [&_code]:bg-dark-bg [&_code]:px-1 [&_code]:rounded [&_pre]:bg-dark-bg [&_pre]:p-3 [&_pre]:rounded-lg [&_strong]:text-text-primary">
                      <ReactMarkdown>{msg.content}</ReactMarkdown>
                    </div>
                  ) : (
                    <p className="text-sm whitespace-pre-wrap">{msg.content}</p>
                  )}
                </div>
              </div>
            ))}
            {sending && (
              <div className="flex justify-start">
                <div className="rounded-lg bg-dark-card border border-dark-border px-3 py-2">
                  <Loader size={14} className="animate-spin text-primary" />
                </div>
              </div>
            )}
          </div>

          <div className="flex gap-2">
            <input value={inputValue} onChange={e => setInputValue(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter' && !sending) handleSend(); }}
              placeholder="Type a message (try 'run shell command')..."
              className="flex-1 rounded-lg border border-dark-border bg-dark-bg px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:border-primary focus:outline-none" />
            <Button variant="primary" onClick={handleSend} disabled={sending}><Send size={16} /></Button>
          </div>
        </Card>

        <Card>
          <div className="flex items-center gap-2 mb-4">
            <Eye size={18} className="text-text-muted" />
            <h3 className="text-lg font-semibold text-text-primary">Pipeline Inspector</h3>
          </div>
          <div className="space-y-4">
            <div>
              <p className="text-xs text-text-muted mb-1">Tenant ID</p>
              <code className="text-sm text-primary-light bg-primary/5 px-2 py-1 rounded">{tenantId}</code>
            </div>
            <div>
              <p className="text-xs text-text-muted mb-2">Permission Profile</p>
              <div className="flex flex-wrap gap-1.5">
                <Badge color="primary">{profile.role}</Badge>
                {profile.tools.map(t => <Badge key={t} color="success">{t}</Badge>)}
              </div>
            </div>
            <div>
              <p className="text-xs text-text-muted mb-2">Plan A — Pre-Execution</p>
              <pre className="rounded-lg bg-dark-bg border border-dark-border p-3 text-xs text-text-secondary whitespace-pre-wrap font-mono">{profile.planA || 'Loading...'}</pre>
            </div>
            <div>
              <p className="text-xs text-text-muted mb-2">Plan E — Post-Execution</p>
              <pre className="rounded-lg bg-dark-bg border border-dark-border p-3 text-xs text-text-secondary whitespace-pre-wrap font-mono">{profile.planE || 'Loading...'}</pre>
            </div>
            <div>
              <p className="text-xs text-text-muted mb-1">Last Plan E Result</p>
              <div className={`rounded-lg px-3 py-2 text-sm ${
                lastPlanE.includes('PASS') ? 'bg-success/10 text-success' : lastPlanE.includes('BLOCKED') ? 'bg-danger/10 text-danger' : 'bg-dark-bg text-text-muted'
              }`}>{lastPlanE}</div>
            </div>
          </div>
        </Card>
      </div>
    </div>
  );
}
