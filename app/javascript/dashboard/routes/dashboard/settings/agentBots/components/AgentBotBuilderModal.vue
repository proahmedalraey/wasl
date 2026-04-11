<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useBranding } from 'shared/composables/useBranding';
import AgentBotsAPI from 'dashboard/api/agentBots';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const dialogRef = ref(null);
const loading = ref(false);
const bot = ref(null);
const flowName = ref('');
const flowDescription = ref('');
const definitionText = ref('');
const validationErrors = ref([]);

const canSubmit = computed(() => {
  if (!bot.value) return false;
  return definitionText.value.trim().length > 0;
});

const defaultDefinition = () => ({
  meta: { allow_loops: false },
  triggers: [],
  variables_schema: {},
  nodes: [
    { id: 'start', type: 'start', data: {}, position: { x: 80, y: 80 } },
    {
      id: 'welcome',
      type: 'send_message',
      data: { text: replaceInstallationName('Welcome to Chatwoot.') },
      position: { x: 320, y: 80 },
    },
    { id: 'end', type: 'end', data: {}, position: { x: 540, y: 80 } },
  ],
  edges: [
    { id: 'e1', source: 'start', target: 'welcome' },
    { id: 'e2', source: 'welcome', target: 'end' },
  ],
});

const parseDefinition = () => {
  try {
    return JSON.parse(definitionText.value);
  } catch (error) {
    return null;
  }
};

const extractBackendErrors = error => {
  const errors = error?.response?.data?.errors;
  return Array.isArray(errors) ? errors : [];
};

const loadFlow = async botId => {
  loading.value = true;
  try {
    const { data } = await AgentBotsAPI.getFlow(botId);
    flowName.value = data.name || '';
    flowDescription.value = data.description || '';
    const definition = data.draft_definition || defaultDefinition();
    definitionText.value = JSON.stringify(definition, null, 2);
    validationErrors.value = [];
  } catch (error) {
    useAlert(t('AGENT_BOTS.BUILDER.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const open = selectedBot => {
  bot.value = selectedBot;
  dialogRef.value.open();
  loadFlow(selectedBot.id);
};

const saveDraft = async () => {
  const definition = parseDefinition();
  if (!definition) {
    validationErrors.value = [t('AGENT_BOTS.BUILDER.INVALID_JSON')];
    useAlert(t('AGENT_BOTS.BUILDER.INVALID_JSON'));
    return;
  }

  loading.value = true;
  try {
    await AgentBotsAPI.updateFlowDraft(bot.value.id, {
      name: flowName.value,
      description: flowDescription.value,
      definition,
    });
    validationErrors.value = [];
    useAlert(t('AGENT_BOTS.BUILDER.SAVE_SUCCESS'));
  } catch (error) {
    validationErrors.value = extractBackendErrors(error);
    const firstError = validationErrors.value[0];
    useAlert(firstError || t('AGENT_BOTS.BUILDER.SAVE_ERROR'));
    if (firstError) return;
    useAlert(t('AGENT_BOTS.BUILDER.SAVE_ERROR'));
  } finally {
    loading.value = false;
  }
};

const validateDraft = async () => {
  const definition = parseDefinition();
  if (!definition) {
    validationErrors.value = [t('AGENT_BOTS.BUILDER.INVALID_JSON')];
    useAlert(t('AGENT_BOTS.BUILDER.INVALID_JSON'));
    return;
  }

  loading.value = true;
  try {
    const { data } = await AgentBotsAPI.validateFlow(bot.value.id, { definition });
    validationErrors.value = data.errors || [];
    if (data.valid) {
      useAlert(t('AGENT_BOTS.BUILDER.VALIDATE_SUCCESS'));
    } else {
      useAlert(validationErrors.value[0] || t('AGENT_BOTS.BUILDER.VALIDATE_ERROR'));
    }
  } catch (error) {
    validationErrors.value = extractBackendErrors(error);
    useAlert(validationErrors.value[0] || t('AGENT_BOTS.BUILDER.VALIDATE_ERROR'));
  } finally {
    loading.value = false;
  }
};

const publishDraft = async () => {
  loading.value = true;
  try {
    const { data } = await AgentBotsAPI.publishFlow(bot.value.id);
    validationErrors.value = [];
    if (data?.published_version) {
      useAlert(t('AGENT_BOTS.BUILDER.PUBLISH_SUCCESS', { version: data.published_version.version }));
    } else {
      useAlert(t('AGENT_BOTS.BUILDER.PUBLISH_SUCCESS_GENERIC'));
    }
  } catch (error) {
    validationErrors.value = extractBackendErrors(error);
    useAlert(validationErrors.value[0] || t('AGENT_BOTS.BUILDER.PUBLISH_ERROR'));
  } finally {
    loading.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('AGENT_BOTS.BUILDER.TITLE', { name: bot?.name || '' })"
    :show-confirm-button="false"
    :show-cancel-button="false"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="flowName"
        :label="t('AGENT_BOTS.BUILDER.FLOW_NAME')"
        :placeholder="t('AGENT_BOTS.BUILDER.FLOW_NAME_PLACEHOLDER')"
      />
      <TextArea
        v-model="flowDescription"
        :label="t('AGENT_BOTS.BUILDER.FLOW_DESCRIPTION')"
        :placeholder="t('AGENT_BOTS.BUILDER.FLOW_DESCRIPTION_PLACEHOLDER')"
      />
      <TextArea
        v-model="definitionText"
        :label="t('AGENT_BOTS.BUILDER.DEFINITION')"
        :placeholder="t('AGENT_BOTS.BUILDER.DEFINITION_PLACEHOLDER')"
        class="[&>textarea]:font-mono [&>textarea]:min-h-[20rem]"
      />

      <div v-if="validationErrors.length" class="rounded-md bg-n-ruby-2 p-3">
        <p class="text-sm font-medium text-n-ruby-11">
          {{ t('AGENT_BOTS.BUILDER.VALIDATION_ERRORS') }}
        </p>
        <ul class="mt-2 list-disc ltr:pl-4 rtl:pr-4 text-sm text-n-ruby-11">
          <li v-for="error in validationErrors" :key="error">
            {{ error }}
          </li>
        </ul>
      </div>

      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          :label="t('AGENT_BOTS.BUILDER.VALIDATE')"
          :is-loading="loading"
          :disabled="!canSubmit"
          @click="validateDraft"
        />
        <Button
          slate
          :label="t('AGENT_BOTS.BUILDER.SAVE_DRAFT')"
          :is-loading="loading"
          :disabled="!canSubmit"
          @click="saveDraft"
        />
        <Button
          :label="t('AGENT_BOTS.BUILDER.PUBLISH')"
          :is-loading="loading"
          :disabled="!canSubmit"
          @click="publishDraft"
        />
      </div>
    </div>
  </Dialog>
</template>
