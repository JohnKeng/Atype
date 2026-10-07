import React, { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { Plus, Sparkles } from "lucide-react";
import { commands } from "@/bindings";
import { useSettings } from "../../../hooks/useSettings";
import { Dialog } from "../../ui/Dialog";
import { Dropdown } from "../../ui/Dropdown";
import { Button } from "../../ui/Button";
import { Input } from "../../ui/Input";
import { SettingContainer } from "../../ui/SettingContainer";

const NEW_ID = "__new__";

interface PromptLibraryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/** Master-detail editor for the LLM prompts (list on the left, editor on the right). */
const PromptLibraryDialog: React.FC<PromptLibraryDialogProps> = ({
  open,
  onOpenChange,
}) => {
  const { t } = useTranslation();
  const { getSetting, updateSetting, refreshSettings } = useSettings();
  const prompts = getSetting("post_process_prompts") || [];
  const activeId = getSetting("post_process_selected_prompt_id") || "";

  const [editingId, setEditingId] = useState<string>(activeId);
  const [name, setName] = useState("");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);

  const editing = useMemo(
    () => prompts.find((p) => p.id === editingId) || null,
    [prompts, editingId],
  );
  const isNew = editingId === NEW_ID;

  // Open on the prompt in use.
  useEffect(() => {
    if (open) setEditingId(activeId || prompts[0]?.id || NEW_ID);
  }, [open]);

  useEffect(() => {
    if (isNew) {
      setName("");
      setText("<transcript>\n${output}\n</transcript>\n\n");
    } else if (editing) {
      setName(editing.name);
      setText(editing.prompt);
    }
  }, [isNew, editing?.id, editing?.name, editing?.prompt]);

  const dirty = isNew
    ? name.trim() !== "" || text.trim() !== ""
    : !!editing &&
      (name.trim() !== editing.name || text.trim() !== editing.prompt.trim());
  const valid = name.trim() !== "" && text.includes("${output}");

  const save = async () => {
    if (!valid) return;
    setBusy(true);
    try {
      if (isNew) {
        const result = await commands.addPostProcessPrompt(
          name.trim(),
          text.trim(),
        );
        await refreshSettings();
        if (result.status === "ok") setEditingId(result.data.id);
      } else if (editing) {
        await commands.updatePostProcessPrompt(
          editing.id,
          name.trim(),
          text.trim(),
        );
        await refreshSettings();
      }
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!editing || prompts.length <= 1) return;
    setBusy(true);
    try {
      await commands.deletePostProcessPrompt(editing.id);
      await refreshSettings();
      setEditingId(prompts.find((p) => p.id !== editing.id)?.id || NEW_ID);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={t("settings.atype.prompts.dialogTitle")}
      description={t("settings.atype.prompts.dialogDescription")}
      closeLabel={t("settings.atype.prompts.close")}
      className="max-w-4xl h-[min(640px,calc(100dvh-3rem))]"
      contentClassName="flex-1 !p-0"
    >
      <div className="flex h-full min-h-0">
        <div className="w-60 shrink-0 border-e border-mid-gray/20 flex flex-col min-h-0">
          <div className="flex-1 overflow-y-auto p-2 space-y-0.5">
            {prompts.map((p) => {
              const selected = p.id === editingId;
              return (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => setEditingId(p.id)}
                  className={`w-full text-start px-3 py-2 rounded-md text-sm flex items-center gap-2 transition-colors cursor-pointer ${
                    selected
                      ? "bg-logo-primary/25 font-semibold"
                      : "hover:bg-mid-gray/10"
                  }`}
                >
                  <span className="flex-1 min-w-0 truncate">{p.name}</span>
                  {p.id === activeId && (
                    <span className="shrink-0 inline-flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded-full bg-background-ui text-white">
                      <Sparkles className="w-3 h-3" aria-hidden="true" />
                      {t("settings.atype.prompts.inUse")}
                    </span>
                  )}
                </button>
              );
            })}
            {isNew && (
              <div className="px-3 py-2 rounded-md text-sm bg-logo-primary/25 font-semibold">
                {t("settings.atype.prompts.untitled")}
              </div>
            )}
          </div>
          <div className="p-2 border-t border-mid-gray/20">
            <Button
              variant="secondary"
              size="sm"
              className="w-full inline-flex items-center justify-center gap-1"
              onClick={() => setEditingId(NEW_ID)}
              disabled={isNew}
            >
              <Plus className="w-4 h-4" aria-hidden="true" />
              {t("settings.atype.prompts.add")}
            </Button>
          </div>
        </div>

        <div className="flex-1 min-w-0 flex flex-col p-4 gap-3 min-h-0">
          <Input
            className="w-full"
            variant="default"
            value={name}
            placeholder={t("settings.atype.prompts.namePlaceholder")}
            onChange={(e) => setName(e.target.value)}
          />
          <textarea
            className="flex-1 min-h-0 w-full resize-none px-3 py-2 text-[13px] leading-relaxed font-mono bg-mid-gray/10 border border-mid-gray/40 rounded-md focus:outline-none focus:border-logo-primary"
            value={text}
            spellCheck={false}
            onChange={(e) => setText(e.target.value)}
          />
          <p className="text-xs text-mid-gray">
            {t("settings.atype.prompts.tip")}
          </p>
          <div className="flex flex-wrap items-center gap-2">
            <Button
              variant="primary"
              size="sm"
              onClick={save}
              disabled={busy || !dirty || !valid}
            >
              {isNew
                ? t("settings.atype.prompts.create")
                : t("settings.atype.prompts.save")}
            </Button>
            {!isNew && editing && editing.id !== activeId && (
              <Button
                variant="secondary"
                size="sm"
                onClick={() =>
                  updateSetting("post_process_selected_prompt_id", editing.id)
                }
              >
                {t("settings.atype.prompts.use")}
              </Button>
            )}
            <div className="flex-1" />
            {isNew ? (
              <Button
                variant="secondary"
                size="sm"
                onClick={() => setEditingId(activeId || prompts[0]?.id)}
              >
                {t("settings.atype.prompts.cancel")}
              </Button>
            ) : (
              <Button
                variant="secondary"
                size="sm"
                onClick={remove}
                disabled={busy || prompts.length <= 1}
              >
                {t("settings.atype.prompts.delete")}
              </Button>
            )}
          </div>
        </div>
      </div>
    </Dialog>
  );
};

/** The 提示詞 row on the 後處理 page: pick the prompt in use, edit in a dialog. */
export const PromptLibraryRow: React.FC = () => {
  const { t } = useTranslation();
  const { getSetting, updateSetting, isUpdating } = useSettings();
  const [open, setOpen] = useState(false);
  const prompts = getSetting("post_process_prompts") || [];
  const activeId = getSetting("post_process_selected_prompt_id") || null;

  return (
    <>
      <SettingContainer
        title={t("settings.postProcessing.prompts.selectedPrompt.title")}
        description={t(
          "settings.postProcessing.prompts.selectedPrompt.description",
        )}
        descriptionMode="tooltip"
        grouped={true}
      >
        <div className="flex items-center gap-2">
          <Dropdown
            className="min-w-56"
            selectedValue={activeId}
            options={prompts.map((p) => ({ value: p.id, label: p.name }))}
            onSelect={(id) =>
              updateSetting("post_process_selected_prompt_id", id)
            }
            disabled={isUpdating("post_process_selected_prompt_id")}
          />
          <Button variant="secondary" size="md" onClick={() => setOpen(true)}>
            {t("settings.atype.prompts.manage")}
          </Button>
        </div>
      </SettingContainer>
      <PromptLibraryDialog open={open} onOpenChange={setOpen} />
    </>
  );
};
