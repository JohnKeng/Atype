import React, { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { open } from "@tauri-apps/plugin-dialog";
import { toast } from "sonner";
import { commands, events } from "@/bindings";
import type { AtypeConfig, AtypeConfigView, AtypeStats } from "@/bindings";
import { SettingsGroup } from "../../ui/SettingsGroup";
import { SettingContainer } from "../../ui/SettingContainer";
import { ToggleSwitch } from "../../ui/ToggleSwitch";
import { Slider } from "../../ui/Slider";
import { Button } from "../../ui/Button";
import { Textarea } from "../../ui/Textarea";
import { DictionaryEditor } from "./DictionaryEditor";
import { Dropdown } from "../../ui/Dropdown";
import { useSettings } from "../../../hooks/useSettings";

const SAMPLE_TEXT = "我们明天下午3:30开会,地点在Costco旁边.";
const STATS_REFRESH_DELAY_MS = 500;

const EMPTY_STATS: AtypeStats = {
  today_chars: 0,
  today_entries: 0,
  week_chars: 0,
  week_entries: 0,
  total_chars: 0,
  total_entries: 0,
};

const toConfig = (view: AtypeConfigView): AtypeConfig => ({
  zh_post_enabled: view.zh_post_enabled,
  llm_timeout_ms: view.llm_timeout_ms,
  llm_on_main_hotkey: view.llm_on_main_hotkey,
  brain_enabled: view.brain_enabled,
  brain_dir: view.brain_dir,
  defaults_version: view.defaults_version,
  dictionary: view.dictionary,
  command_prompt_id: view.command_prompt_id,
  command_timeout_ms: view.command_timeout_ms,
});

const errorText = (error: unknown) =>
  error instanceof Error ? error.message : String(error);

export const AtypeSettings: React.FC = () => {
  const { t, i18n } = useTranslation();
  const { getSetting } = useSettings();
  const prompts = getSetting("post_process_prompts") || [];
  const [config, setConfig] = useState<AtypeConfigView | null>(null);
  const [stats, setStats] = useState<AtypeStats>(EMPTY_STATS);
  const [sample, setSample] = useState(SAMPLE_TEXT);
  const [polished, setPolished] = useState<string | null>(null);
  const configRef = useRef<AtypeConfigView | null>(null);
  const saveSeq = useRef(0);

  const refreshStats = useCallback(async () => {
    try {
      const result = await commands.getAtypeStats();
      if (result.status === "ok") {
        setStats(result.data);
      } else {
        console.error("Failed to load Atype stats:", result.error);
      }
    } catch (error) {
      console.error("Failed to load Atype stats:", error);
    }
  }, []);

  useEffect(() => {
    const load = async () => {
      try {
        const result = await commands.getAtypeConfig();
        if (result.status === "ok") {
          configRef.current = result.data;
          setConfig(result.data);
        } else {
          console.error("Failed to load Atype config:", result.error);
        }
      } catch (error) {
        console.error("Failed to load Atype config:", error);
      }
    };
    load();
    refreshStats();
  }, [refreshStats]);

  // The second brain is written by a Rust listener on the same event, so
  // wait a moment before re-reading the file.
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const unlisten = events.historyUpdatePayload.listen((event) => {
      const { action } = event.payload;
      if (action !== "added" && action !== "updated") return;
      clearTimeout(timer);
      timer = setTimeout(refreshStats, STATS_REFRESH_DELAY_MS);
    });
    return () => {
      clearTimeout(timer);
      unlisten.then((fn) => fn());
    };
  }, [refreshStats]);

  const update = async (patch: Partial<AtypeConfig>) => {
    const current = configRef.current;
    if (!current) return;
    const next: AtypeConfigView = { ...current, ...patch };
    configRef.current = next;
    setConfig(next);
    const seq = ++saveSeq.current;
    try {
      const result = await commands.setAtypeConfig(toConfig(next));
      if (seq !== saveSeq.current) return;
      if (result.status === "ok") {
        configRef.current = result.data;
        setConfig(result.data);
        if ("brain_dir" in patch) refreshStats();
      } else {
        configRef.current = current;
        setConfig(current);
        toast.error(t("settings.atype.errors.save", { error: result.error }));
      }
    } catch (error) {
      if (seq !== saveSeq.current) return;
      configRef.current = current;
      setConfig(current);
      toast.error(t("settings.atype.errors.save", { error: errorText(error) }));
    }
  };

  const chooseFolder = async () => {
    try {
      const selected = await open({
        directory: true,
        multiple: false,
        defaultPath: config?.resolved_brain_dir || undefined,
        title: t("settings.atype.brain.dialogTitle"),
      });
      if (typeof selected === "string" && selected.trim()) {
        await update({ brain_dir: selected });
      }
    } catch (error) {
      toast.error(t("settings.atype.errors.open", { error: errorText(error) }));
    }
  };

  const revealFolder = async () => {
    try {
      const result = await commands.openBrainDir();
      if (result.status === "error") {
        toast.error(t("settings.atype.errors.open", { error: result.error }));
      }
    } catch (error) {
      toast.error(t("settings.atype.errors.open", { error: errorText(error) }));
    }
  };

  const runPolish = async () => {
    try {
      setPolished(await commands.atypePolish(sample));
    } catch (error) {
      toast.error(
        t("settings.atype.errors.polish", { error: errorText(error) }),
      );
    }
  };

  const formatNumber = (n: number) =>
    new Intl.NumberFormat(i18n.language).format(n);

  const periods = [
    {
      key: "today",
      labelKey: "settings.atype.usage.today",
      chars: stats.today_chars,
      entries: stats.today_entries,
    },
    {
      key: "week",
      labelKey: "settings.atype.usage.week",
      chars: stats.week_chars,
      entries: stats.week_entries,
    },
    {
      key: "total",
      labelKey: "settings.atype.usage.total",
      chars: stats.total_chars,
      entries: stats.total_entries,
    },
  ];

  return (
    <div className="max-w-3xl w-full mx-auto space-y-6">
      <SettingsGroup
        title={t("settings.atype.usage.title")}
        description={t("settings.atype.usage.description")}
      >
        <div className="grid grid-cols-3 divide-x divide-mid-gray/20">
          {periods.map((period) => (
            <div key={period.key} className="px-4 py-3 space-y-1">
              <h3 className="text-sm font-medium">{t(period.labelKey)}</h3>
              <div className="flex items-baseline gap-1.5">
                <span className="text-xl font-semibold tabular-nums">
                  {formatNumber(period.chars)}
                </span>
                <span className="text-xs text-mid-gray">
                  {t("settings.atype.usage.chars")}
                </span>
              </div>
              <div className="flex items-baseline gap-1.5">
                <span className="text-sm tabular-nums">
                  {formatNumber(period.entries)}
                </span>
                <span className="text-xs text-mid-gray">
                  {t("settings.atype.usage.entries")}
                </span>
              </div>
            </div>
          ))}
        </div>
      </SettingsGroup>

      {config && (
        <SettingsGroup
          title={t("settings.atype.dictionary.title")}
          description={t("settings.atype.dictionary.description")}
        >
          <div className="px-4 py-3">
            <DictionaryEditor
              entries={config.dictionary}
              onSave={(dictionary) => update({ dictionary })}
            />
          </div>
        </SettingsGroup>
      )}

      {config && (
        <SettingsGroup title={t("settings.atype.brain.title")}>
          <ToggleSwitch
            checked={config.brain_enabled}
            onChange={(enabled) => update({ brain_enabled: enabled })}
            label={t("settings.atype.brain.enabled.label")}
            description={t("settings.atype.brain.enabled.description")}
            grouped={true}
          />
          <SettingContainer
            title={t("settings.atype.brain.folder.title")}
            description={t("settings.atype.brain.folder.description")}
            grouped={true}
            layout="stacked"
          >
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <div
                  className="flex-1 min-w-0 px-2 py-2 bg-mid-gray/10 border border-mid-gray/20 rounded-lg text-xs font-mono truncate select-text cursor-text"
                  title={config.resolved_brain_dir}
                >
                  {config.resolved_brain_dir}
                </div>
                {config.brain_dir === null && (
                  <span className="shrink-0 text-xs text-mid-gray">
                    {t("settings.atype.brain.folder.default")}
                  </span>
                )}
              </div>
              <div className="flex flex-wrap gap-2">
                <Button variant="secondary" size="sm" onClick={chooseFolder}>
                  {t("settings.atype.brain.choose")}
                </Button>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={revealFolder}
                  disabled={!config.resolved_brain_dir}
                >
                  {t("settings.atype.brain.reveal")}
                </Button>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => update({ brain_dir: null })}
                  disabled={config.brain_dir === null}
                >
                  {t("settings.atype.brain.useDefault")}
                </Button>
              </div>
            </div>
          </SettingContainer>
        </SettingsGroup>
      )}

      {config && (
        <SettingsGroup title={t("settings.atype.cleanup.title")}>
          <ToggleSwitch
            checked={config.llm_on_main_hotkey}
            onChange={(enabled) => update({ llm_on_main_hotkey: enabled })}
            label={t("settings.atype.cleanup.mainHotkey.label")}
            description={t("settings.atype.cleanup.mainHotkey.description")}
            grouped={true}
          />
          <Slider
            value={config.llm_timeout_ms}
            onChange={(ms) => update({ llm_timeout_ms: ms })}
            min={1000}
            max={6000}
            step={500}
            label={t("settings.atype.cleanup.timeout.label")}
            description={t("settings.atype.cleanup.timeout.description")}
            formatValue={(ms) =>
              t("settings.atype.cleanup.timeout.value", {
                seconds: (ms / 1000).toFixed(1),
              })
            }
            grouped={true}
          />
          <SettingContainer
            title={t("settings.atype.cleanup.commandPrompt.title")}
            description={t("settings.atype.cleanup.commandPrompt.description")}
            grouped={true}
          >
            <Dropdown
              className="min-w-56"
              options={prompts.map((p) => ({ value: p.id, label: p.name }))}
              selectedValue={config.command_prompt_id}
              onSelect={(id) => update({ command_prompt_id: id })}
            />
          </SettingContainer>
          <Slider
            value={config.command_timeout_ms}
            onChange={(ms) => update({ command_timeout_ms: ms })}
            min={4000}
            max={30000}
            step={1000}
            label={t("settings.atype.cleanup.commandTimeout.label")}
            description={t("settings.atype.cleanup.commandTimeout.description")}
            formatValue={(ms) =>
              t("settings.atype.cleanup.timeout.value", {
                seconds: (ms / 1000).toFixed(0),
              })
            }
            grouped={true}
          />
          <ToggleSwitch
            checked={config.zh_post_enabled}
            onChange={(enabled) => update({ zh_post_enabled: enabled })}
            label={t("settings.atype.cleanup.zhPost.label")}
            description={t("settings.atype.cleanup.zhPost.description")}
            grouped={true}
          />
        </SettingsGroup>
      )}

      <SettingsGroup title={t("settings.atype.tryIt.title")}>
        <SettingContainer
          title={t("settings.atype.tryIt.input")}
          description={t("settings.atype.cleanup.zhPost.description")}
          grouped={true}
          layout="stacked"
        >
          <div className="space-y-2">
            <Textarea
              className="w-full"
              variant="compact"
              value={sample}
              placeholder={t("settings.atype.tryIt.placeholder")}
              onChange={(e) => setSample(e.target.value)}
            />
            <Button
              variant="primary"
              size="sm"
              onClick={runPolish}
              disabled={!sample.trim()}
            >
              {t("settings.atype.tryIt.button")}
            </Button>
            {polished !== null && (
              <div className="space-y-1">
                <h4 className="text-xs font-medium text-mid-gray">
                  {t("settings.atype.tryIt.result")}
                </h4>
                <div className="px-3 py-2 min-h-10 bg-mid-gray/10 border border-mid-gray/20 rounded-md text-sm whitespace-pre-wrap break-words select-text cursor-text">
                  {polished}
                </div>
              </div>
            )}
          </div>
        </SettingContainer>
      </SettingsGroup>
    </div>
  );
};
