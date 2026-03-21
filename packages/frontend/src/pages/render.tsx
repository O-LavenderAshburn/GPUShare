import { useState, useEffect, useRef } from 'react';
import { useWebHaptics } from '../lib/haptics';
import { render } from '../lib/api';
import type { RenderJobResponse, RenderJobCreateRequest } from '@shared/types/render';

const STATUS_STYLES: Record<string, string> = {
  queued: 'bg-yellow-900/50 text-yellow-300 border-yellow-700',
  rendering: 'bg-blue-900/50 text-blue-300 border-blue-700',
  complete: 'bg-green-900/50 text-green-300 border-green-700',
  failed: 'bg-red-900/50 text-red-300 border-red-700',
};

export function RenderPage() {
  const { trigger } = useWebHaptics();
  const [jobs, setJobs] = useState<RenderJobResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

  const [engine, setEngine] = useState<'cycles' | 'eevee'>('cycles');
  const [frameStart, setFrameStart] = useState('1');
  const [frameEnd, setFrameEnd] = useState('1');
  const [resX, setResX] = useState('1920');
  const [resY, setResY] = useState('1080');
  const [outputFormat, setOutputFormat] = useState('PNG');

  function fetchJobs() {
    render.listJobs().then(setJobs).catch(() => {}).finally(() => setLoading(false));
  }

  useEffect(() => {
    fetchJobs();
  }, []);

  // Auto-refresh while any jobs are active
  useEffect(() => {
    const hasActive = jobs.some(j => j.status === 'queued' || j.status === 'rendering');
    if (!hasActive) return;
    const interval = setInterval(fetchJobs, 5000);
    return () => clearInterval(interval);
  }, [jobs]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const file = fileRef.current?.files?.[0];
    if (!file) return;

    setSubmitting(true);
    setError('');
    try {
      const params: RenderJobCreateRequest = {
        engine,
        frame_start: Number(frameStart),
        frame_end: Number(frameEnd),
        resolution_x: Number(resX),
        resolution_y: Number(resY),
        output_format: outputFormat,
      };
      await render.createJob(file, params);
      trigger('success');
      fetchJobs();
      if (fileRef.current) fileRef.current.value = '';
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create job');
    } finally {
      setSubmitting(false);
    }
  }

  function handleCancel(id: string) {
    trigger('buzz');
    render.cancelJob(id).then(fetchJobs).catch(() => {});
  }

  const totalFrames = (j: RenderJobResponse) => j.frame_end - j.frame_start + 1;

  return (
    <div className="p-6 space-y-6 max-w-6xl pb-20 md:pb-0">
      <h2 className="text-lg font-semibold">Render Jobs</h2>

      <form onSubmit={handleSubmit} className="bg-gray-800 rounded-xl p-6 space-y-4">
        <h3 className="font-medium">New Render Job</h3>

        {error && (
          <div className="bg-red-900/50 border border-red-700 text-red-200 text-sm rounded-lg p-3">{error}</div>
        )}

        <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div className="col-span-2 md:col-span-3">
            <label className="block text-sm text-gray-400 mb-1">Blend File</label>
            <input
              ref={fileRef}
              type="file"
              accept=".blend"
              required
              className="w-full text-sm text-gray-400 file:mr-4 file:rounded-lg file:border-0 file:bg-gray-700 file:px-4 file:py-2 file:text-sm file:text-white hover:file:bg-gray-600"
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Engine</label>
            <select
              value={engine}
              onChange={e => setEngine(e.target.value as 'cycles' | 'eevee')}
              className="w-full bg-gray-700 border border-gray-600 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-blue-500"
            >
              <option value="cycles">Cycles</option>
              <option value="eevee">Eevee</option>
            </select>
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Frame Start</label>
            <input type="number" value={frameStart} onChange={e => setFrameStart(e.target.value)} min={1}
              className="w-full bg-gray-700 border border-gray-600 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-blue-500" />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Frame End</label>
            <input type="number" value={frameEnd} onChange={e => setFrameEnd(e.target.value)} min={1}
              className="w-full bg-gray-700 border border-gray-600 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-blue-500" />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Resolution X</label>
            <input type="number" value={resX} onChange={e => setResX(e.target.value)} min={1}
              className="w-full bg-gray-700 border border-gray-600 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-blue-500" />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Resolution Y</label>
            <input type="number" value={resY} onChange={e => setResY(e.target.value)} min={1}
              className="w-full bg-gray-700 border border-gray-600 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-blue-500" />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Output Format</label>
            <select value={outputFormat} onChange={e => setOutputFormat(e.target.value)}
              className="w-full bg-gray-700 border border-gray-600 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-blue-500">
              <option value="PNG">PNG</option>
              <option value="JPEG">JPEG</option>
              <option value="OPEN_EXR">EXR</option>
            </select>
          </div>
        </div>

        <button
          type="submit"
          disabled={submitting}
          className="bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-lg px-6 py-2.5 text-sm font-medium transition-colors"
        >
          {submitting ? 'Uploading...' : 'Submit Job'}
        </button>
      </form>

      <div className="bg-gray-800 rounded-xl overflow-hidden">
        {loading ? (
          <div className="p-6 text-center text-gray-500">Loading...</div>
        ) : jobs.length === 0 ? (
          <div className="p-6 text-center text-gray-500">No render jobs yet</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-700 text-gray-400 text-left">
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Engine</th>
                <th className="px-4 py-3 font-medium">Frames</th>
                <th className="px-4 py-3 font-medium">Resolution</th>
                <th className="px-4 py-3 font-medium">Cost</th>
                <th className="px-4 py-3 font-medium">Created</th>
                <th className="px-4 py-3 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {jobs.map(job => (
                <tr key={job.id} className="border-b border-gray-700/50">
                  <td className="px-4 py-3">
                    <span className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-medium ${STATUS_STYLES[job.status] || ''}`}>
                      {job.status}
                      {job.status === 'rendering' && ` (${job.frames_done}/${totalFrames(job)})`}
                    </span>
                  </td>
                  <td className="px-4 py-3 capitalize">{job.engine}</td>
                  <td className="px-4 py-3">{job.frame_start}-{job.frame_end}</td>
                  <td className="px-4 py-3">{job.resolution_x}x{job.resolution_y}</td>
                  <td className="px-4 py-3">{job.cost_nzd !== null ? `$${job.cost_nzd.toFixed(4)}` : '-'}</td>
                  <td className="px-4 py-3 text-gray-400">{new Date(job.created_at).toLocaleDateString()}</td>
                  <td className="px-4 py-3 space-x-2">
                    {job.download_url && (
                      <a href={job.download_url} target="_blank" rel="noreferrer"
                        className="text-blue-400 hover:text-blue-300 text-xs">Download</a>
                    )}
                    {(job.status === 'queued' || job.status === 'rendering') && (
                      <button onClick={() => handleCancel(job.id)}
                        className="text-red-400 hover:text-red-300 text-xs">Cancel</button>
                    )}
                    {job.error_message && (
                      <span className="text-red-400 text-xs" title={job.error_message}>Error</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
