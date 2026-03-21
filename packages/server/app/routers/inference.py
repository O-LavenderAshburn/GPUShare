"""OpenAI-compatible inference endpoints."""

import json
import time
import uuid
from collections.abc import AsyncGenerator
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.lib.billing import (
    calculate_inference_cost,
    check_balance_ok,
    get_inference_cost_per_token,
    write_ledger_entry,
)
from app.lib.ollama import chat_completion, chat_completion_stream, count_tokens
from app.models import UsageLog, User
from app.routers.auth import get_current_user
from app.schemas.inference import (
    ChatCompletionChoice,
    ChatCompletionRequest,
    ChatCompletionResponse,
    ChatMessage,
    ModelInfo,
    ModelsResponse,
    UsageInfo,
)

router = APIRouter(prefix="/v1/inference", tags=["inference"])


# ---------------------------------------------------------------------------
# POST /chat/completions
# ---------------------------------------------------------------------------


@router.post("/chat/completions")
async def create_chat_completion(
    body: ChatCompletionRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """OpenAI-compatible chat completion (streaming and non-streaming)."""
    settings = get_settings()

    # Check user balance against hard limit
    if not await check_balance_ok(db, user.id, user.hard_limit_nzd):
        raise HTTPException(
            status_code=402,
            detail="Insufficient balance. Please top up your account.",
        )

    # Count input tokens
    input_text = " ".join(m.content for m in body.messages)
    input_tokens = count_tokens(input_text)

    messages = [{"role": m.role, "content": m.content} for m in body.messages]

    if body.stream:
        return StreamingResponse(
            _stream_response(
                model=body.model,
                messages=messages,
                input_tokens=input_tokens,
                temperature=body.temperature,
                max_tokens=body.max_tokens,
                user=user,
                db=db,
            ),
            media_type="text/event-stream",
        )

    # Non-streaming path
    result = await chat_completion(
        model=body.model,
        messages=messages,
        temperature=body.temperature,
        max_tokens=body.max_tokens,
    )

    # Extract assistant response
    assistant_content = result.get("message", {}).get("content", "")
    output_tokens = count_tokens(assistant_content)

    # Calculate cost and record usage
    cost, kwh = calculate_inference_cost(input_tokens, output_tokens)

    usage_log = UsageLog(
        user_id=user.id,
        model=body.model,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cost_nzd=cost,
        kwh=kwh,
    )
    db.add(usage_log)

    await write_ledger_entry(
        db=db,
        user_id=user.id,
        amount=-cost,
        entry_type="inference_usage",
        description=f"Inference: {body.model} ({input_tokens}+{output_tokens} tokens)",
    )

    completion_id = f"chatcmpl-{uuid.uuid4().hex[:24]}"
    created = int(time.time())

    return ChatCompletionResponse(
        id=completion_id,
        created=created,
        model=body.model,
        choices=[
            ChatCompletionChoice(
                index=0,
                message=ChatMessage(role="assistant", content=assistant_content),
                finish_reason="stop",
            )
        ],
        usage=UsageInfo(
            prompt_tokens=input_tokens,
            completion_tokens=output_tokens,
            total_tokens=input_tokens + output_tokens,
        ),
    )


async def _stream_response(
    model: str,
    messages: list[dict],
    input_tokens: int,
    temperature: float | None,
    max_tokens: int | None,
    user: User,
    db: AsyncSession,
) -> AsyncGenerator[str, None]:
    """Generate SSE chunks for a streaming chat completion."""
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:24]}"
    created = int(time.time())
    collected_content = ""

    async for chunk in chat_completion_stream(
        model=model,
        messages=messages,
        temperature=temperature,
        max_tokens=max_tokens,
    ):
        # Extract content from Ollama chunk
        content = chunk.get("message", {}).get("content", "")
        if content:
            collected_content += content

        done = chunk.get("done", False)
        finish_reason = "stop" if done else None

        sse_chunk = {
            "id": completion_id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [
                {
                    "index": 0,
                    "delta": {"content": content} if content else {},
                    "finish_reason": finish_reason,
                }
            ],
        }

        yield f"data: {json.dumps(sse_chunk)}\n\n"

    # After stream ends, record usage
    output_tokens = count_tokens(collected_content)
    cost, kwh = calculate_inference_cost(input_tokens, output_tokens)

    usage_log = UsageLog(
        user_id=user.id,
        model=model,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cost_nzd=cost,
        kwh=kwh,
    )
    db.add(usage_log)

    await write_ledger_entry(
        db=db,
        user_id=user.id,
        amount=-cost,
        entry_type="inference_usage",
        description=f"Inference: {model} ({input_tokens}+{output_tokens} tokens)",
    )
    await db.commit()

    yield "data: [DONE]\n\n"


# ---------------------------------------------------------------------------
# GET /models
# ---------------------------------------------------------------------------


@router.get("/models", response_model=ModelsResponse)
async def list_models(
    user: User = Depends(get_current_user),
):
    """Return the list of configured models with pricing info."""
    settings = get_settings()
    cost_per_token = get_inference_cost_per_token()

    models = [
        ModelInfo(
            id=model_name,
            cost_per_million_tokens=float(cost_per_token * Decimal("1000000")),
        )
        for model_name in settings.models_list
    ]

    return ModelsResponse(data=models)
