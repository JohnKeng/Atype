import React, { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import type { DictEntry } from "@/bindings";
import { Input } from "../../ui/Input";
import { Button } from "../../ui/Button";

interface DraftRow {
  term: string;
  aliases: string;
}

// Aliases are typed as one line; commas (half or full width), 、 and
// semicolons all separate them.
const splitAliases = (text: string) =>
  text
    .split(/[,，、;；]/)
    .map((a) => a.trim())
    .filter(Boolean);

const toDraft = (entries: DictEntry[]): DraftRow[] =>
  entries.map((e) => ({ term: e.term, aliases: e.aliases.join("、") }));

const toEntries = (rows: DraftRow[]): DictEntry[] =>
  rows
    .filter((r) => r.term.trim())
    .map((r) => ({ term: r.term.trim(), aliases: splitAliases(r.aliases) }));

interface DictionaryEditorProps {
  entries: DictEntry[];
  onSave: (entries: DictEntry[]) => void;
}

export const DictionaryEditor: React.FC<DictionaryEditorProps> = ({
  entries,
  onSave,
}) => {
  const { t } = useTranslation();
  const [rows, setRows] = useState<DraftRow[]>(() => toDraft(entries));
  const [newRow, setNewRow] = useState<DraftRow>({ term: "", aliases: "" });

  // Follow the saved list (sanitized by the backend) after each save.
  useEffect(() => {
    setRows(toDraft(entries));
  }, [entries]);

  const commit = (next: DraftRow[]) => {
    const cleaned = toEntries(next);
    if (JSON.stringify(cleaned) !== JSON.stringify(entries)) onSave(cleaned);
  };

  const editRow = (index: number, patch: Partial<DraftRow>) =>
    setRows((prev) =>
      prev.map((r, i) => (i === index ? { ...r, ...patch } : r)),
    );

  const removeRow = (index: number) => {
    const next = rows.filter((_, i) => i !== index);
    setRows(next);
    commit(next);
  };

  const addRow = () => {
    if (!newRow.term.trim()) return;
    const next = [newRow, ...rows];
    setRows(next);
    setNewRow({ term: "", aliases: "" });
    commit(next);
  };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Input
          className="w-36"
          variant="compact"
          value={newRow.term}
          placeholder={t("settings.atype.dictionary.termPlaceholder")}
          onChange={(e) => setNewRow({ ...newRow, term: e.target.value })}
          onKeyDown={(e) => e.key === "Enter" && addRow()}
        />
        <Input
          className="flex-1 min-w-48"
          variant="compact"
          value={newRow.aliases}
          placeholder={t("settings.atype.dictionary.aliasesPlaceholder")}
          onChange={(e) => setNewRow({ ...newRow, aliases: e.target.value })}
          onKeyDown={(e) => e.key === "Enter" && addRow()}
        />
        <Button
          variant="primary"
          size="sm"
          onClick={addRow}
          disabled={!newRow.term.trim()}
        >
          {t("settings.atype.dictionary.add")}
        </Button>
      </div>

      {rows.length === 0 ? (
        <p className="text-xs text-mid-gray">
          {t("settings.atype.dictionary.empty")}
        </p>
      ) : (
        <div className="divide-y divide-mid-gray/15 border border-mid-gray/20 rounded-lg">
          <div className="flex gap-2 px-2 py-1.5 text-xs text-mid-gray">
            <span className="w-36">{t("settings.atype.dictionary.term")}</span>
            <span className="flex-1">
              {t("settings.atype.dictionary.aliases")}
            </span>
          </div>
          {rows.map((row, index) => (
            <div key={index} className="flex items-center gap-2 px-2 py-1.5">
              <Input
                className="w-36"
                variant="compact"
                value={row.term}
                onChange={(e) => editRow(index, { term: e.target.value })}
                onBlur={() => commit(rows)}
              />
              <Input
                className="flex-1 min-w-0"
                variant="compact"
                value={row.aliases}
                placeholder={t("settings.atype.dictionary.soundOnly")}
                onChange={(e) => editRow(index, { aliases: e.target.value })}
                onBlur={() => commit(rows)}
              />
              <Button
                variant="secondary"
                size="sm"
                onClick={() => removeRow(index)}
                aria-label={t("settings.atype.dictionary.remove")}
              >
                {t("settings.atype.dictionary.remove")}
              </Button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
