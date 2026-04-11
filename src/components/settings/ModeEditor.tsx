import React, { useState, useEffect } from "react";
import { useTranslation } from "react-i18next";
import type { ProcessingMode } from "@/bindings";
import { Input } from "../ui/Input";
import { Textarea } from "../ui/Textarea";
import { Button } from "../ui/Button";

interface ModeEditorProps {
  mode: ProcessingMode | null;
  onSave: (name: string, description: string, prompt: string) => void;
  onCancel: () => void;
  isCreating: boolean;
}

export const ModeEditor: React.FC<ModeEditorProps> = ({
  mode,
  onSave,
  onCancel,
  isCreating,
}) => {
  const { t } = useTranslation();
  const [name, setName] = useState(mode?.name ?? "");
  const [description, setDescription] = useState(mode?.description ?? "");
  const [prompt, setPrompt] = useState(mode?.prompt ?? "");

  useEffect(() => {
    setName(mode?.name ?? "");
    setDescription(mode?.description ?? "");
    setPrompt(mode?.prompt ?? "");
  }, [mode]);

  const handleSubmit = () => {
    if (name.trim()) {
      onSave(name.trim(), description.trim(), prompt.trim());
    }
  };

  return (
    <div className="space-y-4 p-4 bg-background border border-mid-gray/20 rounded-lg">
      <div className="space-y-2">
        <label className="text-xs font-medium text-mid-gray uppercase tracking-wide">
          {t("settings.modes.modeName")}
        </label>
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={t("settings.modes.modeNamePlaceholder")}
        />
      </div>
      <div className="space-y-2">
        <label className="text-xs font-medium text-mid-gray uppercase tracking-wide">
          {t("settings.modes.modeDescription")}
        </label>
        <Input
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder={t("settings.modes.modeDescriptionPlaceholder")}
        />
      </div>
      <div className="space-y-2">
        <label className="text-xs font-medium text-mid-gray uppercase tracking-wide">
          {t("settings.modes.modePrompt")}
        </label>
        <Textarea
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          placeholder={t("settings.modes.modePromptPlaceholder")}
          rows={8}
        />
      </div>
      <div className="flex gap-2 justify-end">
        <Button variant="ghost" onClick={onCancel}>
          {t("settings.modes.cancel")}
        </Button>
        <Button onClick={handleSubmit} disabled={!name.trim()}>
          {isCreating
            ? t("settings.modes.createMode")
            : t("settings.modes.save")}
        </Button>
      </div>
    </div>
  );
};
