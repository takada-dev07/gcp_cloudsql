from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import delete, desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Todo
from app.db.session import get_db
from app.schemas.todo import TodoCreate, TodoRead, TodoUpdate

router = APIRouter(prefix="/api/todos", tags=["todos"])


@router.post("", response_model=TodoRead, status_code=status.HTTP_201_CREATED)
async def create_todo(payload: TodoCreate, db: AsyncSession = Depends(get_db)) -> TodoRead:
    todo = Todo(title=payload.title)
    db.add(todo)
    await db.commit()
    await db.refresh(todo)
    return todo


@router.get("", response_model=list[TodoRead])
async def list_todos(db: AsyncSession = Depends(get_db)) -> list[TodoRead]:
    result = await db.execute(select(Todo).order_by(desc(Todo.created_at)))
    return list(result.scalars().all())


@router.get("/{todo_id}", response_model=TodoRead)
async def get_todo(todo_id: int, db: AsyncSession = Depends(get_db)) -> TodoRead:
    todo = await db.get(Todo, todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")
    return todo


@router.patch("/{todo_id}", response_model=TodoRead)
async def update_todo(
    todo_id: int, payload: TodoUpdate, db: AsyncSession = Depends(get_db)
) -> TodoRead:
    todo = await db.get(Todo, todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    if payload.title is not None:
        todo.title = payload.title
    if payload.is_done is not None:
        todo.is_done = payload.is_done

    await db.commit()
    await db.refresh(todo)
    return todo


@router.delete("/{todo_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_todo(todo_id: int, db: AsyncSession = Depends(get_db)) -> Response:
    todo = await db.get(Todo, todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    await db.execute(delete(Todo).where(Todo.id == todo_id))
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


